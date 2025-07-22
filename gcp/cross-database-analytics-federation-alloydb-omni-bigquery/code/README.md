# Infrastructure as Code for Cross-Database Analytics Federation with AlloyDB Omni and BigQuery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Database Analytics Federation with AlloyDB Omni and BigQuery".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - BigQuery Admin
  - Dataplex Admin
  - Cloud Functions Admin
  - Cloud Storage Admin
  - Cloud SQL Admin
  - Service Account Admin
- For on-premises AlloyDB Omni: Infrastructure capable of running PostgreSQL (minimum 4 vCPUs, 16GB RAM)
- Network connectivity between on-premises and Google Cloud (VPN or Cloud Interconnect recommended)
- Estimated cost: $50-100 per day for testing environment

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create federation-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-bucket/federation-config/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe federation-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
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

## Architecture Overview

This infrastructure deploys:

- **BigQuery datasets** for federated analytics workspace and cloud-native data
- **Cloud SQL PostgreSQL instance** (simulating AlloyDB Omni on-premises)
- **BigQuery external connection** for federation between cloud and on-premises data
- **Cloud Storage bucket** as data lake foundation with organized directory structure
- **Cloud Functions** for metadata orchestration and workflow automation
- **Dataplex lake and assets** for unified data governance and catalog management
- **IAM service accounts** with appropriate permissions for cross-service authentication

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | No |
| `random_suffix` | Unique suffix for resource names | Auto-generated | No |
| `alloydb_instance_memory` | Memory allocation for AlloyDB simulation | `8GB` | No |
| `alloydb_instance_cpu` | CPU allocation for AlloyDB simulation | `2` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | string | - | Yes |
| `region` | Primary deployment region | string | `us-central1` | No |
| `zone` | Primary deployment zone | string | `us-central1-a` | No |
| `environment` | Environment name (dev/staging/prod) | string | `dev` | No |
| `enable_apis` | Enable required Google Cloud APIs | bool | `true` | No |
| `bucket_location` | Cloud Storage bucket location | string | `US` | No |
| `alloydb_database_flags` | Custom database flags for AlloyDB simulation | map(string) | `{}` | No |

## Post-Deployment Configuration

After infrastructure deployment, complete these steps:

1. **Populate sample data**:
   ```bash
   # Connect to Cloud SQL instance and create sample transactional data
   gcloud sql connect $(terraform output -raw alloydb_instance_name) \
       --user=postgres \
       --database=transactions
   
   # Execute sample data scripts (provided in scripts/sample_data.sql)
   ```

2. **Test federated queries**:
   ```bash
   # Execute federated analytics query
   bq query --use_legacy_sql=false \
       --format=table \
       "SELECT * FROM \`$(terraform output -raw project_id).analytics_federation.customer_lifetime_value\`"
   ```

3. **Verify metadata synchronization**:
   ```bash
   # Test Cloud Function for metadata sync
   curl -X POST \
       -H "Content-Type: application/json" \
       -d "{\"project_id\":\"$(terraform output -raw project_id)\",\"connection_id\":\"$(terraform output -raw connection_id)\"}" \
       $(terraform output -raw function_url)
   ```

## Monitoring and Observability

### BigQuery Monitoring

- Monitor federated query performance in BigQuery console
- Set up alerts for query failures or performance degradation
- Track data transfer costs for federated queries

### Dataplex Governance

- Review data discovery results in Dataplex console
- Monitor data quality metrics and lineage tracking
- Configure governance policies for automated compliance

### Cloud Functions Monitoring

- Monitor function execution logs in Cloud Logging
- Set up alerts for metadata synchronization failures
- Track function performance and error rates

## Security Considerations

### Network Security

- Configure VPC firewalls for restricted access to Cloud SQL instance
- Implement Private Google Access for internal traffic
- Use VPN or Cloud Interconnect for production on-premises connectivity

### Data Security

- Enable Cloud SQL encryption at rest and in transit
- Configure BigQuery column-level security for sensitive data
- Implement IAM conditions for fine-grained access control

### Service Account Security

- Use least privilege principle for all service accounts
- Regularly rotate service account keys
- Enable audit logging for all service account activities

## Troubleshooting

### Common Issues

1. **Federation connection failures**:
   ```bash
   # Check connection status
   bq show --connection --location=${REGION} ${PROJECT_ID}.${REGION}.${CONNECTION_ID}
   
   # Test basic connectivity
   bq query --use_legacy_sql=false "SELECT 1 FROM EXTERNAL_QUERY('${CONNECTION_ID}', 'SELECT 1')"
   ```

2. **Dataplex discovery issues**:
   ```bash
   # Check asset status
   gcloud dataplex assets list --location=${REGION} --lake=${LAKE_ID}
   
   # Trigger manual discovery
   gcloud dataplex discovery-events create --location=${REGION} --lake=${LAKE_ID}
   ```

3. **Cloud Function authentication errors**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:serviceAccount:${SERVICE_ACCOUNT}"
   ```

### Performance Optimization

- **Federated Query Optimization**: Use appropriate WHERE clauses to push down filters
- **Connection Pooling**: Implement connection pooling for high-frequency queries
- **Result Caching**: Enable query result caching for frequently accessed data
- **Indexing**: Create appropriate indexes on AlloyDB Omni tables for federation

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete federation-deployment \
    --location=${REGION}

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual cleanup verification
gcloud sql instances list
gcloud dataplex lakes list --location=${REGION}
gsutil ls
```

## Advanced Configuration

### Production Deployment Considerations

1. **High Availability**: Deploy AlloyDB Omni with read replicas across multiple zones
2. **Disaster Recovery**: Implement cross-region backup and recovery strategies
3. **Monitoring**: Deploy comprehensive monitoring with Cloud Operations Suite
4. **Cost Optimization**: Implement BigQuery slots reservations for predictable workloads

### Integration Patterns

1. **CI/CD Integration**: Integrate with Cloud Build for automated deployments
2. **GitOps**: Use Config Sync for infrastructure configuration management
3. **Multi-Environment**: Deploy separate environments with Terraform workspaces
4. **Cross-Cloud**: Extend federation to include AWS RDS or Azure SQL Database

## Support and Resources

### Documentation

- [AlloyDB Omni Documentation](https://cloud.google.com/alloydb/docs/omni)
- [BigQuery Federated Queries](https://cloud.google.com/bigquery/docs/federated-queries)
- [Dataplex Universal Catalog](https://cloud.google.com/dataplex/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)

### Best Practices

- [BigQuery Best Practices](https://cloud.google.com/bigquery/docs/best-practices)
- [Cloud SQL Security Best Practices](https://cloud.google.com/sql/docs/postgres/security-best-practices)
- [Dataplex Data Governance](https://cloud.google.com/dataplex/docs/data-governance)

### Community

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [GitHub - GoogleCloudPlatform](https://github.com/GoogleCloudPlatform)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud provider documentation.

## License

This infrastructure code is provided under the same license as the parent recipe repository.