# Infrastructure as Code for Architecting Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for automated execution

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Following IAM permissions:
  - Security Admin
  - Database Admin
  - Workflows Admin
  - Asset Inventory Viewer
  - Cloud Functions Admin
  - Service Account Admin
  - BigQuery Admin
  - Storage Admin
- Basic understanding of database governance and compliance frameworks
- Estimated cost: $50-100 for testing resources over deployment period

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/database-governance \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com \
    --config-file=main.yaml
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize and deploy with Terraform
cd terraform/
terraform init
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh
```

## What Gets Deployed

This Infrastructure as Code creates a comprehensive database governance solution including:

### Core Infrastructure
- **Sample Database Fleet**: Cloud SQL, Spanner, and Bigtable instances for governance testing
- **Service Account**: Dedicated service account with minimal required permissions
- **IAM Bindings**: Proper role assignments for governance automation

### Governance Components
- **BigQuery Dataset**: Asset inventory data warehouse for compliance reporting
- **Cloud Storage Bucket**: Secure storage for compliance reports and governance artifacts
- **Pub/Sub Topic**: Real-time notifications for database asset changes
- **Cloud Workflows**: Automated governance workflow for compliance evaluation

### Monitoring & Automation
- **Cloud Function**: Automated compliance reporting with configurable schedules
- **Cloud Scheduler**: Periodic governance checks and report generation
- **Log-based Metrics**: Custom metrics for governance events and compliance scoring
- **Alert Policies**: Proactive notifications for governance violations

### AI-Powered Insights
- **Database Center Integration**: AI-powered fleet management with Gemini chat interface
- **Cloud Asset Inventory**: Automated resource discovery and compliance monitoring
- **Custom Dashboards**: Comprehensive governance visibility and reporting

## Configuration Options

### Infrastructure Manager Variables

Customize your deployment by modifying the configuration in `infrastructure-manager/main.yaml`:

```yaml
# Project and location settings
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"

# Database fleet configuration
sql_tier: "db-f1-micro"
spanner_nodes: 1
bigtable_nodes: 1

# Automation settings
governance_schedule: "0 */6 * * *"  # Every 6 hours
backup_retention_days: 7
```

### Terraform Variables

Customize your deployment using `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Database configuration
sql_tier        = "db-f1-micro"
spanner_nodes   = 1
bigtable_nodes  = 1

# Governance settings
governance_schedule       = "0 */6 * * *"
backup_retention_days    = 7
enable_deletion_protection = true

# Monitoring configuration
alert_email = "admin@yourcompany.com"
```

### Bash Script Environment Variables

Configure deployment parameters using environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export SQL_TIER="db-f1-micro"
export SPANNER_NODES=1
export BIGTABLE_NODES=1
export GOVERNANCE_SCHEDULE="0 */6 * * *"
export ALERT_EMAIL="admin@yourcompany.com"
```

## Accessing the Solution

After deployment, access your database governance solution:

1. **Database Center Dashboard**:
   ```
   https://console.cloud.google.com/database-center?project=${PROJECT_ID}
   ```

2. **Asset Inventory in BigQuery**:
   ```bash
   # Query database assets
   bq query --use_legacy_sql=false \
   "SELECT asset_type, COUNT(*) as count FROM \`${PROJECT_ID}.database_governance.asset_inventory\` GROUP BY asset_type"
   ```

3. **Compliance Reports**:
   ```bash
   # List generated reports
   gsutil ls gs://db-governance-assets-*/compliance-reports/
   ```

4. **Gemini AI Chat**:
   - Navigate to Database Center
   - Use the Gemini chat interface for natural language governance queries
   - Example queries: "Show me databases without backup enabled" or "What are the security recommendations for my fleet?"

## Validation & Testing

### Verify Deployment

```bash
# Check database instances
gcloud sql instances list
gcloud spanner instances list
gcloud bigtable instances list

# Verify governance components
gcloud workflows list
gcloud functions list
gcloud scheduler jobs list

# Test compliance reporting
curl -X GET "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/compliance-reporter?project_id=${PROJECT_ID}"
```

### Test Governance Workflows

```bash
# Manual workflow execution
gcloud workflows execute database-governance-workflow \
    --data='{"test": "governance_validation"}'

# Check workflow execution history
gcloud workflows executions list --workflow=database-governance-workflow --limit=5
```

### Validate Monitoring

```bash
# Check custom metrics
gcloud logging metrics list --filter="name:database_compliance_score"

# Test alert policies
gcloud alpha monitoring policies list
```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/database-governance
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are removed
gcloud sql instances list
gcloud spanner instances list
gcloud bigtable instances list
gcloud functions list
gcloud workflows list
bq ls ${PROJECT_ID}:
gsutil ls
```

## Cost Optimization

### Resource Sizing Recommendations

- **Development/Testing**: Use `db-f1-micro` for Cloud SQL, single node configurations
- **Production**: Scale based on actual fleet size and governance requirements
- **Storage**: Configure lifecycle policies for compliance reports in Cloud Storage

### Cost Monitoring

```bash
# Enable billing export for cost tracking
bq mk --dataset --location=${REGION} ${PROJECT_ID}:billing_export

# Monitor database costs specifically
gcloud billing budgets list
```

## Security Considerations

### Service Account Permissions

The solution creates a service account with minimal required permissions:
- `roles/cloudasset.viewer`: Read asset inventory data
- `roles/workflows.invoker`: Execute governance workflows
- `roles/monitoring.metricWriter`: Write custom governance metrics

### Data Protection

- All compliance reports are stored in Cloud Storage with encryption at rest
- Database instances are created with backup enabled and deletion protection
- IAM policies follow the principle of least privilege

### Network Security

- Database instances use private IPs where supported
- Cloud Functions use VPC connector for secure communication
- Asset inventory data is restricted to authorized service accounts

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Database Creation Failures**:
   ```bash
   # Check API enablement
   gcloud services list --enabled --filter="name:sqladmin.googleapis.com"
   ```

3. **Workflow Execution Failures**:
   ```bash
   # Check workflow logs
   gcloud workflows executions describe EXECUTION_ID \
       --workflow=database-governance-workflow \
       --location=${REGION}
   ```

### Debug Mode

Enable debug logging for scripts:

```bash
export DEBUG=true
./scripts/deploy.sh
```

### Log Analysis

```bash
# View governance function logs
gcloud functions logs read compliance-reporter --limit=50

# Monitor workflow execution logs
gcloud logging read "resource.type=workflows.googleapis.com/Workflow" --limit=20
```

## Advanced Configuration

### Custom Compliance Policies

Modify the governance workflow to include custom compliance checks:

1. Edit the workflow definition in `terraform/workflows.tf` or `infrastructure-manager/main.yaml`
2. Add custom validation functions
3. Redeploy the infrastructure

### Integration with External Systems

- **ITSM Integration**: Modify Cloud Functions to create tickets in external systems
- **Slack Notifications**: Add Slack webhook integration to alert policies
- **Custom Dashboards**: Use Cloud Monitoring API to create custom governance dashboards

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Validate IAM permissions and API enablement
4. Use `gcloud` debug mode for detailed error information

## Useful Commands

```bash
# Quick health check of all components
./scripts/health-check.sh

# Generate compliance report manually
gcloud functions call compliance-reporter --data='{}'

# Export governance metrics
gcloud monitoring time-series list --filter="metric.type=custom.googleapis.com/database/governance_score"

# Update governance schedule
gcloud scheduler jobs update http governance-scheduler --schedule="0 */4 * * *"
```

This infrastructure provides a complete, production-ready database governance solution that can be customized for your specific requirements and compliance needs.