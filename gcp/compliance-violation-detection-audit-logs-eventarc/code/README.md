# Infrastructure as Code for Compliance Violation Detection with Cloud Audit Logs and Eventarc

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Compliance Violation Detection with Cloud Audit Logs and Eventarc".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Developer
  - Eventarc Admin
  - Pub/Sub Admin
  - BigQuery Admin
  - Logging Admin
  - Cloud Monitoring Editor
  - Service Account Admin

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager enabled
- `gcloud` version 400.0.0 or later

#### Terraform
- Terraform CLI v1.0+ installed
- Google Cloud provider v4.0+ configured

## Architecture Overview

This infrastructure deploys:
- **Cloud Functions**: Serverless compliance detection logic
- **Eventarc Triggers**: Event routing from audit logs to functions
- **Pub/Sub Topics**: Reliable messaging for compliance alerts
- **BigQuery Dataset**: Data warehouse for violation analysis
- **Cloud Monitoring**: Alerting and dashboard capabilities
- **Cloud Logging**: Enhanced audit log configuration

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create compliance-monitoring \
    --location=${REGION} \
    --source-git-repo="https://github.com/your-org/compliance-infra" \
    --source-git-ref="main" \
    --source-input-dir="infrastructure-manager/"

# Monitor deployment progress
gcloud infra-manager deployments describe compliance-monitoring \
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

# Set environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud functions list --regions=${REGION}
gcloud eventarc triggers list --location=${REGION}
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | Current project | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `compliance-detector` | No |
| `dataset_name` | BigQuery dataset name | `compliance_logs` | No |
| `topic_name` | Pub/Sub topic name | `compliance-alerts` | No |
| `enable_data_access_logs` | Enable data access audit logs | `true` | No |
| `notification_email` | Email for alerts | `""` | No |

### Customization Examples

#### Terraform Variables File

Create `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-west1"
function_name = "custom-compliance-detector"
dataset_name = "security_compliance_logs"
topic_name = "security-violations"
enable_data_access_logs = true
notification_email = "security-team@company.com"
```

#### Infrastructure Manager Configuration

Modify `main.yaml` to customize resource configurations:

```yaml
# Example: Change function memory allocation
resources:
  - name: compliance-function
    type: cloud-function
    properties:
      memory: 1024
      timeout: 540
```

## Monitoring and Validation

### Verify Deployment

```bash
# Check Cloud Function status
gcloud functions describe compliance-detector \
    --region=${REGION} \
    --format="table(status,updateTime)"

# Verify Eventarc trigger
gcloud eventarc triggers list \
    --location=${REGION} \
    --filter="name:audit-log-trigger"

# Check BigQuery dataset
bq ls -d ${PROJECT_ID}:compliance_logs

# Verify Pub/Sub topic
gcloud pubsub topics list --filter="name:compliance-alerts"
```

### Test Compliance Detection

```bash
# Generate test audit log event
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:test@example.com" \
    --role="roles/viewer"

# Remove test binding
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
    --member="user:test@example.com" \
    --role="roles/viewer"

# Check for violations in BigQuery (wait 30-60 seconds)
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.compliance_logs.violations\` 
     WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)"
```

### View Function Logs

```bash
# View recent function executions
gcloud functions logs read compliance-detector \
    --region=${REGION} \
    --limit=20

# Monitor real-time logs
gcloud functions logs tail compliance-detector \
    --region=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete compliance-monitoring \
    --location=${REGION}

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
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

# Manual verification
gcloud functions list --regions=${REGION}
gcloud eventarc triggers list --location=${REGION}
```

## Troubleshooting

### Common Issues

#### Function Deployment Fails
```bash
# Check service enablement
gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --filter="bindings.members:$(gcloud config get-value account)"
```

#### Eventarc Trigger Not Working
```bash
# Check trigger status
gcloud eventarc triggers describe audit-log-trigger \
    --location=${REGION} \
    --format="table(conditions,destination)"

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --filter="bindings.members:${PROJECT_ID}@appspot.gserviceaccount.com"
```

#### BigQuery Access Issues
```bash
# Check dataset permissions
bq show --format=prettyjson ${PROJECT_ID}:compliance_logs

# Test write access
bq query --use_legacy_sql=false \
    "SELECT 1 as test" \
    --destination_table=${PROJECT_ID}:compliance_logs.test_table
```

### Log Analysis

```bash
# Function error logs
gcloud logging read \
    "resource.type=cloud_function AND resource.labels.function_name=compliance-detector AND severity>=ERROR" \
    --limit=10

# Eventarc delivery issues
gcloud logging read \
    "resource.type=eventarc_trigger AND resource.labels.trigger_name=audit-log-trigger" \
    --limit=10
```

## Security Considerations

### IAM Best Practices
- Function uses least-privilege service account
- BigQuery dataset access restricted to compliance team
- Pub/Sub topic secured with appropriate IAM bindings

### Audit Log Configuration
- Data Access logs enabled for sensitive services
- Log retention configured per compliance requirements
- Log export configured for long-term storage

### Network Security
- Functions deployed with VPC connector when needed
- Private Google Access enabled for enhanced security
- Cloud Armor protection for external endpoints

## Cost Optimization

### Resource Sizing
- Cloud Function memory optimized for workload (512MB default)
- BigQuery partitioned tables for cost-effective querying
- Pub/Sub message retention aligned with business needs

### Monitoring Usage
```bash
# Function invocation metrics
gcloud monitoring metrics list \
    --filter="metric.type:cloudfunctions.googleapis.com/function/executions"

# BigQuery storage costs
bq query --use_legacy_sql=false \
    "SELECT 
       table_name, 
       ROUND(size_bytes/1024/1024/1024, 2) as size_gb,
       ROUND(size_bytes/1024/1024/1024 * 0.02, 2) as monthly_cost_usd
     FROM \`${PROJECT_ID}.compliance_logs.__TABLES__\`"
```

## Compliance Framework Alignment

### Supported Frameworks
- **SOC 2**: Automated monitoring and alerting capabilities
- **ISO 27001**: Continuous security monitoring and incident response
- **PCI DSS**: Data access monitoring and violation detection
- **GDPR**: Data processing activity monitoring and privacy controls

### Audit Requirements
- All violations stored with immutable timestamps
- Comprehensive audit trail for investigation capabilities
- Automated reporting for compliance officer reviews

## Support and Documentation

### Additional Resources
- [Google Cloud Audit Logs Documentation](https://cloud.google.com/logging/docs/audit)
- [Eventarc Best Practices](https://cloud.google.com/eventarc/docs/best-practices)
- [Cloud Functions Security Guide](https://cloud.google.com/functions/docs/securing)
- [BigQuery Security and Compliance](https://cloud.google.com/bigquery/docs/security)

### Getting Help
- For infrastructure issues: Review logs using the troubleshooting section
- For compliance questions: Consult your organization's compliance team
- For Google Cloud support: Use the Google Cloud Console support features

---

**Note**: This infrastructure implements production-ready compliance monitoring. Review and customize the configuration based on your organization's specific compliance requirements and security policies.