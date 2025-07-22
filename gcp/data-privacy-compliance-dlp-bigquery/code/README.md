# Infrastructure as Code for Data Privacy Compliance with Cloud DLP and BigQuery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Privacy Compliance with Cloud DLP and BigQuery".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud Project with billing enabled
- Following APIs enabled:
  - Cloud Data Loss Prevention (DLP) API
  - BigQuery API
  - Cloud Storage API
  - Cloud Functions API
  - Cloud Logging API
  - Cloud Monitoring API
- Appropriate IAM permissions:
  - BigQuery Admin
  - Storage Admin
  - Cloud Functions Admin
  - DLP Admin
  - Project Editor (or specific service permissions)
- For Terraform: Terraform >= 1.0 installed

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/dlp-compliance \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/repo" \
    --git-source-directory="gcp/data-privacy-compliance-dlp-bigquery/code/infrastructure-manager" \
    --git-source-ref="main"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# When prompted, confirm with 'yes'
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
```

## Configuration

### Infrastructure Manager

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region (default: us-central1)
- `bucket_name_suffix`: Unique suffix for Cloud Storage bucket
- `dataset_name`: BigQuery dataset name (default: privacy_compliance)
- `function_name_suffix`: Unique suffix for Cloud Functions

### Terraform

Edit `terraform/terraform.tfvars` to customize:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
bucket_name_suffix    = "unique-suffix"
dataset_name         = "privacy_compliance"
function_name_suffix = "unique-suffix"
dlp_job_description  = "Privacy compliance scan for sensitive data"
```

### Bash Scripts

Environment variables can be set before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BUCKET_NAME_SUFFIX="your-suffix"
export DATASET_NAME="privacy_compliance"
export FUNCTION_NAME_SUFFIX="your-suffix"
```

## Deployed Resources

This infrastructure creates the following Google Cloud resources:

### Core Infrastructure
- **Cloud Storage Bucket**: Stores data files for DLP scanning with lifecycle policies
- **BigQuery Dataset**: Contains compliance analytics tables
  - `dlp_scan_results`: Detailed findings from DLP scans
  - `compliance_summary`: High-level compliance metrics
- **Cloud Function**: Automated remediation and result processing
- **Pub/Sub Topic**: Message queue for DLP scan notifications

### DLP Configuration
- **DLP Inspection Template**: Defines detection rules for PII and sensitive data
- **DLP Job**: Automated scanning of Cloud Storage data
- **DLP InfoTypes**: Configured to detect:
  - Email addresses
  - Phone numbers
  - Social Security numbers
  - Credit card numbers
  - Person names
  - IP addresses

### Security & Monitoring
- **IAM Roles**: Least privilege access for service accounts
- **Cloud Logging**: Centralized logging for all components
- **Cloud Monitoring**: Performance and health monitoring

## Testing the Deployment

After deployment, test the privacy compliance system:

1. **Upload Test Data**:
   ```bash
   # Upload sample files with PII
   echo "John Doe,john@example.com,555-123-4567,123-45-6789" > test_data.csv
   gsutil cp test_data.csv gs://your-bucket-name/data/
   ```

2. **Trigger DLP Scan**:
   ```bash
   # Check DLP job status
   gcloud dlp jobs list --filter="state:RUNNING"
   ```

3. **Verify Results in BigQuery**:
   ```bash
   bq query --use_legacy_sql=false \
   "SELECT info_type, likelihood, COUNT(*) as count 
    FROM \`${PROJECT_ID}.privacy_compliance.dlp_scan_results\` 
    GROUP BY info_type, likelihood"
   ```

4. **Check Cloud Function Logs**:
   ```bash
   gcloud functions logs read dlp-remediation-function --limit 20
   ```

## Monitoring and Compliance

### BigQuery Analytics

Use these SQL queries for compliance reporting:

```sql
-- Daily compliance summary
SELECT 
  DATE(scan_timestamp) as scan_date,
  COUNT(DISTINCT file_path) as files_scanned,
  COUNT(*) as total_findings,
  SUM(CASE WHEN likelihood IN ('LIKELY', 'VERY_LIKELY') THEN 1 ELSE 0 END) as high_risk_findings
FROM `your-project.privacy_compliance.dlp_scan_results`
GROUP BY DATE(scan_timestamp)
ORDER BY scan_date DESC;

-- PII type distribution
SELECT 
  info_type,
  likelihood,
  COUNT(*) as finding_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM `your-project.privacy_compliance.dlp_scan_results`
GROUP BY info_type, likelihood
ORDER BY finding_count DESC;
```

### Cloud Monitoring Dashboards

Access pre-configured dashboards for:
- DLP scan job performance
- Cloud Function execution metrics
- BigQuery query performance
- Storage bucket access patterns

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/dlp-compliance
```

### Using Terraform

```bash
cd terraform/
terraform destroy
# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
# Follow the prompts to confirm deletion
```

## Cost Optimization

### Expected Costs

- **Cloud DLP**: Based on data volume scanned (~$1 per GB)
- **BigQuery**: Storage and query costs (~$0.02 per GB stored)
- **Cloud Storage**: Standard storage rates (~$0.02 per GB per month)
- **Cloud Functions**: Pay-per-invocation (~$0.40 per million requests)
- **Pub/Sub**: Message processing (~$0.40 per million messages)

### Cost Management Tips

1. **Set up lifecycle policies** on Cloud Storage to automatically delete old scan data
2. **Configure BigQuery table expiration** for historical compliance data
3. **Use DLP sampling** for large datasets to reduce scanning costs
4. **Monitor with Budget Alerts** to track spending against expectations

## Security Considerations

### Data Protection
- All data is encrypted in transit and at rest using Google Cloud's default encryption
- Cloud Storage buckets use uniform bucket-level access controls
- BigQuery datasets implement column-level security for sensitive findings

### Access Control
- Service accounts follow least privilege principle
- DLP inspection templates restrict access to compliance team
- Cloud Function execution uses dedicated service account with minimal permissions

### Compliance Features
- Audit logging enabled for all data access and modifications
- Data retention policies align with GDPR requirements (365 days default)
- Geographic data residency controls through region selection

## Troubleshooting

### Common Issues

1. **DLP Job Fails to Start**:
   - Verify Cloud DLP API is enabled
   - Check service account permissions
   - Ensure Pub/Sub topic exists

2. **Cloud Function Errors**:
   - Check function logs: `gcloud functions logs read [function-name]`
   - Verify BigQuery dataset and table exist
   - Ensure proper IAM roles for function service account

3. **BigQuery Access Denied**:
   - Verify BigQuery API is enabled
   - Check dataset permissions
   - Ensure service account has BigQuery Data Editor role

4. **Storage Access Issues**:
   - Verify bucket exists and is accessible
   - Check uniform bucket-level access settings
   - Ensure proper Cloud Storage permissions

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check DLP job details
gcloud dlp jobs describe [JOB_ID]

# Monitor Cloud Function performance
gcloud functions describe [FUNCTION_NAME] --region=${REGION}
```

## Advanced Configuration

### Custom DLP Rules

To add custom detection rules, modify the DLP inspection template:

```yaml
# In infrastructure-manager/main.yaml or terraform/main.tf
custom_info_types:
  - name: "EMPLOYEE_ID"
    regex: "EMP-[0-9]{6}"
  - name: "CUSTOMER_ID"
    regex: "CUST-[A-Z]{2}[0-9]{8}"
```

### Multi-Region Deployment

For global compliance requirements:

```bash
# Deploy to multiple regions
export REGIONS=("us-central1" "europe-west1" "asia-east1")
for region in "${REGIONS[@]}"; do
  export REGION=$region
  ./scripts/deploy.sh
done
```

### Integration with External Systems

The infrastructure supports integration with:
- **SIEM Systems**: Via Cloud Logging exports
- **Ticketing Systems**: Via Cloud Function webhooks
- **Data Catalogs**: Via BigQuery metadata exports
- **Compliance Dashboards**: Via BigQuery BI Engine

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for solution context
2. **Google Cloud Documentation**: 
   - [Sensitive Data Protection](https://cloud.google.com/sensitive-data-protection)
   - [BigQuery](https://cloud.google.com/bigquery/docs)
   - [Cloud Functions](https://cloud.google.com/functions/docs)
3. **Terraform Provider Documentation**: [Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Infrastructure Manager Documentation**: [Google Cloud Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

To improve this infrastructure code:

1. Follow Google Cloud best practices
2. Test changes in a development environment
3. Update documentation for any configuration changes
4. Ensure compliance with data privacy regulations