# Enterprise Data Discovery with Data Catalog and Cloud Workflows - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying an automated enterprise data discovery solution using Google Cloud Platform services including Data Catalog, Cloud Workflows, Cloud Functions, and BigQuery.

## Architecture Overview

The infrastructure deploys the following components:

- **Data Catalog Tag Templates**: Define metadata classification schemas for data sensitivity and quality metrics
- **Cloud Function**: Intelligent metadata extraction engine for automated discovery and analysis
- **Cloud Workflows**: Orchestration engine for coordinating parallel discovery across multiple data sources
- **Cloud Scheduler**: Automated scheduling for daily and weekly discovery operations
- **BigQuery Datasets**: Sample datasets for testing discovery capabilities
- **Cloud Storage Buckets**: Sample buckets for testing content analysis and classification
- **IAM Service Account**: Dedicated service account with least-privilege permissions

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud CLI** installed and configured
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** version >= 1.0 installed
   ```bash
   terraform --version
   ```

3. **Required Google Cloud APIs** enabled (automatically enabled by Terraform):
   - Data Catalog API
   - Cloud Workflows API
   - Cloud Functions API
   - Cloud Scheduler API
   - BigQuery API
   - Cloud Build API
   - Cloud Storage API

4. **IAM Permissions** for the account running Terraform:
   - Project Editor or equivalent custom role
   - Service Account Admin
   - Security Admin (for IAM role assignments)

5. **Estimated Costs**: $50-100/month for moderate enterprise usage

## Quick Start

### 1. Clone and Navigate
```bash
cd gcp/enterprise-data-discovery-catalog-workflows/code/terraform/
```

### 2. Configure Variables
Create a `terraform.tfvars` file:
```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
resource_prefix = "data-discovery"
environment    = "dev"

# Customize discovery schedules (optional)
scheduler_config = {
  daily_schedule  = "0 2 * * *"    # 2 AM daily
  weekly_schedule = "0 1 * * 0"    # 1 AM Sunday
  time_zone      = "America/New_York"
}

# Resource labeling
labels = {
  project     = "enterprise-data-discovery"
  managed_by  = "terraform"
  team        = "data-engineering"
  environment = "dev"
}
```

### 3. Initialize and Deploy
```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment
```bash
# Check if resources were created successfully
terraform output

# Test the Cloud Function manually
curl -X POST "$(terraform output -raw cloud_function | jq -r '.trigger_url')" \
  -H "Content-Type: application/json" \
  -d '{"project_id": "YOUR_PROJECT_ID", "location": "us-central1"}'

# Execute the workflow manually
gcloud workflows run "$(terraform output -raw workflow | jq -r '.name')" \
  --location="$(terraform output -raw region)" \
  --data='{"suffix": "test"}'
```

## Configuration Options

### Core Configuration
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `resource_prefix` | Prefix for resource names | `data-discovery` | No |
| `environment` | Environment name | `dev` | No |

### Data Catalog Configuration
The `tag_templates` variable allows customization of metadata classification schemas:

```hcl
tag_templates = {
  custom_classification = {
    display_name = "Custom Data Classification"
    description  = "Organization-specific data classification"
    fields = {
      security_level = {
        display_name = "Security Level"
        type         = "ENUM"
        is_required  = true
        enum_values  = ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "TOP_SECRET"]
      }
      data_owner = {
        display_name = "Data Owner"
        type         = "STRING"
        is_required  = true
      }
    }
  }
}
```

### Cloud Function Configuration
Customize the metadata extraction function:

```hcl
function_config = {
  name          = "custom-metadata-extractor"
  runtime       = "python311"
  memory        = "2Gi"        # Increase for large datasets
  timeout       = 540          # 9 minutes max
  max_instances = 20           # Scale for high load
  min_instances = 1            # Keep warm instances
}
```

### Scheduling Configuration
Customize automated discovery timing:

```hcl
scheduler_config = {
  daily_schedule   = "0 3 * * *"           # 3 AM daily
  weekly_schedule  = "0 2 * * 1"           # 2 AM Monday
  time_zone       = "America/Los_Angeles"  # Pacific Time
  description     = "Custom discovery schedule"
}
```

### Sample Data Configuration
Control test datasets creation:

```hcl
sample_datasets = {
  analytics_prod = {
    description   = "Production analytics data"
    location     = "US"
    friendly_name = "Analytics Production"
    tables = {
      user_events = {
        description = "User interaction events"
        schema = [
          { name = "user_id", type = "STRING" },
          { name = "event_type", type = "STRING" },
          { name = "timestamp", type = "TIMESTAMP" }
        ]
      }
    }
  }
}
```

## Operational Guide

### Manual Discovery Execution
```bash
# Execute discovery workflow manually
gcloud workflows run data-discovery-workflow-SUFFIX \
  --location=us-central1 \
  --data='{"suffix": "SUFFIX", "comprehensive": true}'

# Check execution status
gcloud workflows executions list \
  --workflow=data-discovery-workflow-SUFFIX \
  --location=us-central1

# Get execution results
gcloud workflows executions describe EXECUTION_ID \
  --workflow=data-discovery-workflow-SUFFIX \
  --location=us-central1
```

### Monitoring and Troubleshooting
```bash
# View Cloud Function logs
gcloud functions logs read metadata-extractor-SUFFIX \
  --gen2 \
  --region=us-central1 \
  --limit=50

# Check workflow execution logs
gcloud logging read 'resource.type="workflows.googleapis.com/Workflow"' \
  --limit=20 \
  --format=json

# Monitor scheduler job status
gcloud scheduler jobs list --location=us-central1

# View Data Catalog entries
gcloud data-catalog entries search \
  --location=us-central1 \
  --query="type=table"
```

### Performance Tuning

#### For Large Data Estates (1000+ datasets)
```hcl
function_config = {
  memory        = "2Gi"
  timeout       = 540
  max_instances = 50
}

scheduler_config = {
  daily_schedule  = "0 1 * * *"  # Earlier start time
  weekly_schedule = "0 23 * * 6" # Saturday night
}
```

#### For High-Frequency Discovery
```hcl
scheduler_config = {
  daily_schedule = "0 */6 * * *"  # Every 6 hours
}
```

## Security Considerations

### Service Account Permissions
The deployment creates a dedicated service account with minimal required permissions:
- `datacatalog.admin` - Create and manage catalog entries
- `bigquery.dataViewer` - Read BigQuery metadata
- `storage.objectViewer` - Read storage metadata
- `cloudsql.viewer` - Read Cloud SQL metadata
- `logging.logWriter` - Write application logs
- `monitoring.metricWriter` - Write custom metrics

### Network Security
- Cloud Function uses HTTPS endpoints with authentication
- All inter-service communication uses Google Cloud's private network
- No public IP addresses required for internal components

### Data Protection
- All data in transit encrypted with TLS 1.2+
- Data at rest encrypted with Google-managed keys
- Metadata only - no actual data content is processed
- Audit logging enabled for all operations

### Customizing Security

#### Restrict Function Access
```hcl
# Remove this resource to require authentication
# google_cloudfunctions2_function_iam_member.invoker
```

#### Add Custom IAM Roles
```hcl
variable "additional_roles" {
  default = [
    "roles/cloudsql.client",  # For Cloud SQL discovery
    "roles/spanner.viewer"    # For Spanner discovery
  ]
}
```

## Troubleshooting

### Common Issues

#### 1. API Not Enabled Error
```bash
Error: Error creating function: googleapi: Error 403: Cloud Functions API has not been used
```
**Solution**: Enable APIs manually or wait for Terraform dependency resolution:
```bash
gcloud services enable cloudfunctions.googleapis.com
terraform apply
```

#### 2. Quota Exceeded
```bash
Error: Quota exceeded for quota metric 'Function deployments per region per day'
```
**Solution**: Request quota increase or deploy in different region:
```hcl
variable "region" {
  default = "us-east1"  # Try different region
}
```

#### 3. Workflow Execution Fails
Check workflow execution logs:
```bash
gcloud workflows executions describe EXECUTION_ID \
  --workflow=WORKFLOW_NAME \
  --location=REGION \
  --format="value(error)"
```

#### 4. Function Timeout
Increase function timeout for large datasets:
```hcl
function_config = {
  timeout = 540  # Maximum 9 minutes
  memory  = "2Gi" # More memory for processing
}
```

### Debug Mode
Enable detailed logging by setting environment variables:
```hcl
service_config {
  environment_variables = {
    LOG_LEVEL = "DEBUG"
    ENABLE_TRACE = "true"
  }
}
```

## Cleanup

### Destroy Infrastructure
```bash
# Remove all Terraform-managed resources
terraform destroy

# Confirm deletion
terraform show  # Should show no resources
```

### Manual Cleanup (if needed)
```bash
# Delete any remaining storage buckets
gsutil ls -p YOUR_PROJECT_ID | grep data-discovery | xargs -I {} gsutil rm -r {}

# Delete any remaining BigQuery datasets
bq ls --project_id=YOUR_PROJECT_ID | grep discovery | awk '{print $1}' | xargs -I {} bq rm -r -f {}
```

## Customization Examples

### Industry-Specific Modifications

#### Healthcare (HIPAA Compliance)
```hcl
tag_templates = {
  hipaa_classification = {
    display_name = "HIPAA Data Classification"
    fields = {
      phi_status = {
        display_name = "PHI Status"
        type = "ENUM"
        enum_values = ["NON_PHI", "LIMITED_PHI", "FULL_PHI"]
      }
      retention_period = {
        display_name = "Retention Period (Years)"
        type = "DOUBLE"
      }
    }
  }
}
```

#### Financial Services (SOX Compliance)
```hcl
tag_templates = {
  sox_classification = {
    display_name = "SOX Data Classification"
    fields = {
      sox_relevance = {
        display_name = "SOX Relevance"
        type = "ENUM"
        enum_values = ["SOX_CRITICAL", "SOX_RELEVANT", "NON_SOX"]
      }
      audit_frequency = {
        display_name = "Audit Frequency"
        type = "STRING"
      }
    }
  }
}
```

### Multi-Environment Deployment
```hcl
# environments/dev.tfvars
environment = "dev"
function_config = {
  max_instances = 5
}
scheduler_config = {
  daily_schedule = "0 */12 * * *"  # Twice daily for testing
}

# environments/prod.tfvars
environment = "prod"
function_config = {
  max_instances = 20
  min_instances = 2
}
scheduler_config = {
  daily_schedule = "0 2 * * *"     # Once daily
  weekly_schedule = "0 1 * * 0"    # Weekly comprehensive
}
```

## Support and Maintenance

### Monitoring Checklist
- [ ] Scheduler jobs running successfully
- [ ] Function execution within timeout limits
- [ ] Workflow executions completing without errors
- [ ] Data Catalog entries being created
- [ ] Tag templates applied correctly

### Regular Maintenance
1. **Monthly**: Review discovery quality metrics
2. **Quarterly**: Update tag templates for new requirements
3. **Annually**: Review and optimize IAM permissions

### Getting Help
- Review Terraform documentation: https://registry.terraform.io/providers/hashicorp/google
- Google Cloud Data Catalog docs: https://cloud.google.com/data-catalog/docs
- Cloud Workflows documentation: https://cloud.google.com/workflows/docs
- Report issues in the recipe repository

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-12 | Initial Terraform implementation |