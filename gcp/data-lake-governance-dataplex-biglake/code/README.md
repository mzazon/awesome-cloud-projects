# Infrastructure as Code for Data Lake Governance with Dataplex and BigLake

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Lake Governance with Dataplex and BigLake".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud project with billing enabled
- `gcloud` CLI installed and configured (version 450.0.0 or later)
- Appropriate IAM permissions:
  - Dataplex Admin (`roles/dataplex.admin`)
  - BigQuery Admin (`roles/bigquery.admin`)
  - Cloud Functions Developer (`roles/cloudfunctions.developer`)
  - Storage Admin (`roles/storage.admin`)
  - BigQuery Connection Admin (`roles/bigquery.connectionAdmin`)
- For Terraform: Terraform CLI installed (version 1.0.0 or later)

## Architecture Overview

This implementation creates:

- **Dataplex Lake and Zone**: Hierarchical organization for data governance
- **Cloud Storage Bucket**: Sample data storage with governance policies
- **BigQuery Dataset**: Analytics workspace with BigLake tables
- **BigQuery Connection**: External connection for multi-cloud data access
- **BigLake Tables**: Governed external tables for secure data access
- **Dataplex Assets**: Automatic discovery and cataloging configuration
- **Cloud Function**: Serverless governance monitoring and quality assessment
- **IAM Bindings**: Least-privilege security configuration

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/data-lake-governance \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars.example"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/data-lake-governance
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/validate.sh
```

## Configuration Variables

### Infrastructure Manager / Terraform Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `project_id` | string | Google Cloud project ID | Required |
| `region` | string | Primary region for resources | `us-central1` |
| `zone` | string | Primary zone for resources | `us-central1-a` |
| `lake_name` | string | Name for Dataplex lake | `enterprise-data-lake` |
| `zone_name` | string | Name for Dataplex zone | `raw-data-zone` |
| `dataset_name` | string | BigQuery dataset name | `governance_analytics` |
| `bucket_name` | string | Cloud Storage bucket name | Auto-generated |
| `connection_name` | string | BigQuery connection name | Auto-generated |
| `enable_discovery` | bool | Enable automatic data discovery | `true` |
| `enable_quality_monitoring` | bool | Enable quality monitoring function | `true` |
| `labels` | map(string) | Resource labels for governance | `{}` |

### Bash Script Environment Variables

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization variables
export LAKE_NAME="enterprise-data-lake"
export ZONE_NAME="raw-data-zone"
export DATASET_NAME="governance_analytics"
export ENABLE_DISCOVERY="true"
export ENABLE_MONITORING="true"
```

## Deployment Process

### 1. Initial Setup

The deployment process includes:

1. **API Enablement**: Activates required Google Cloud APIs
2. **Storage Creation**: Creates Cloud Storage bucket with sample data
3. **IAM Configuration**: Sets up service accounts and permissions
4. **Network Setup**: Configures VPC and firewall rules if needed

### 2. Core Infrastructure

1. **Dataplex Lake**: Creates hierarchical data organization structure
2. **Dataplex Zone**: Establishes governance boundaries and policies
3. **BigQuery Resources**: Sets up dataset, connection, and BigLake tables
4. **Discovery Assets**: Configures automatic data cataloging

### 3. Governance Components

1. **Quality Monitoring**: Deploys Cloud Function for automated quality checks
2. **Lineage Tracking**: Configures data lineage and profiling tasks
3. **Policy Enforcement**: Applies fine-grained access controls

### 4. Sample Data

The deployment includes sample customer and transaction data to demonstrate governance capabilities:

- Customer data with PII for data classification testing
- Transaction data for quality monitoring and analytics
- Structured CSV format with proper schema definition

## Validation & Testing

### Verify Dataplex Resources

```bash
# Check lake status
gcloud dataplex lakes describe ${LAKE_NAME} \
    --location=${REGION}

# List discovered entities
gcloud dataplex entities list \
    --location=${REGION} \
    --lake=${LAKE_NAME} \
    --zone=${ZONE_NAME}
```

### Test BigLake Analytics

```bash
# Query customer analytics
bq query --use_legacy_sql=false \
    "SELECT country, COUNT(*) as customer_count
     FROM \`${PROJECT_ID}.${DATASET_NAME}.customers_biglake\`
     GROUP BY country"

# Test cross-table joins
bq query --use_legacy_sql=false \
    "SELECT c.country, COUNT(t.transaction_id) as transactions
     FROM \`${PROJECT_ID}.${DATASET_NAME}.customers_biglake\` c
     JOIN \`${PROJECT_ID}.${DATASET_NAME}.transactions_biglake\` t
       ON c.customer_id = t.customer_id
     GROUP BY c.country"
```

### Test Governance Monitoring

```bash
# Get Cloud Function URL
FUNCTION_URL=$(gcloud functions describe governance-monitor \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test monitoring endpoint
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"action": "monitor_quality"}'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/data-lake-governance \
    --async

# Monitor deletion progress
gcloud infra-manager operations list \
    --location=${REGION} \
    --filter="target:data-lake-governance"
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm deletion
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
./scripts/validate-cleanup.sh
```

## Cost Optimization

### Resource Cost Estimates

| Resource Type | Estimated Monthly Cost | Notes |
|---------------|----------------------|-------|
| Cloud Storage | $5-20 | Based on data volume and access patterns |
| BigQuery | $10-50 | Pay-per-query pricing, depends on usage |
| Dataplex | $20-100 | Based on discovery frequency and data volume |
| Cloud Functions | $1-5 | Serverless pricing, minimal overhead |
| **Total** | **$36-175** | Varies by usage patterns |

### Cost Optimization Tips

1. **Storage Classes**: Use appropriate Cloud Storage classes for data lifecycle
2. **Query Optimization**: Optimize BigQuery queries to reduce processing costs
3. **Discovery Scheduling**: Adjust Dataplex discovery frequency based on data change patterns
4. **Function Optimization**: Right-size Cloud Function memory and timeout settings

## Security Considerations

### Access Control

- **Least Privilege**: All service accounts follow minimal permission principles
- **Resource-Level Security**: Fine-grained access control on BigLake tables
- **Network Security**: Private endpoints and VPC controls where applicable

### Data Protection

- **Encryption**: All data encrypted at rest and in transit
- **Access Logging**: Comprehensive audit trails for compliance
- **Data Classification**: Automatic PII detection and classification
- **Quality Monitoring**: Continuous data integrity validation

### Compliance Features

- **GDPR Support**: Data lineage and deletion capabilities
- **SOX Compliance**: Audit trails and access controls
- **HIPAA Ready**: Encryption and access logging for healthcare data
- **Financial Services**: Regulatory reporting and governance controls

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable dataplex.googleapis.com bigquery.googleapis.com
   ```

2. **IAM Permissions**:
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **BigLake Connection Issues**:
   ```bash
   # Verify connection status
   bq show --connection --location=${REGION} ${CONNECTION_NAME}
   ```

4. **Discovery Not Working**:
   ```bash
   # Check Dataplex discovery jobs
   gcloud dataplex jobs list --location=${REGION} --lake=${LAKE_NAME}
   ```

### Debug Commands

```bash
# Enable debug logging
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account.json"
export CLOUDSDK_CORE_VERBOSITY="debug"

# Check resource status
gcloud logging read "resource.type=dataplex_lake" --limit=50

# Verify function logs
gcloud functions logs read governance-monitor --region=${REGION}
```

## Customization

### Advanced Configuration

1. **Multi-Region Setup**: Modify variables to deploy across multiple regions
2. **Custom Data Sources**: Add additional storage buckets and data formats
3. **Extended Monitoring**: Implement custom quality rules and alerting
4. **Integration APIs**: Connect with existing governance tools and workflows

### Scaling Considerations

- **High Volume Data**: Configure Dataplex autoscaling for large datasets
- **Global Deployment**: Use multi-region BigQuery for global analytics
- **Enterprise Integration**: Implement LDAP/AD integration for user management
- **Performance Tuning**: Optimize BigQuery slot reservations and caching

## Support

### Documentation Links

- [Dataplex Documentation](https://cloud.google.com/dataplex/docs)
- [BigLake Documentation](https://cloud.google.com/bigquery/docs/biglake-intro)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Use `gcloud feedback` to report Google Cloud CLI issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development project
2. Follow Google Cloud best practices
3. Update documentation for any new features
4. Verify all IaC implementations remain in sync