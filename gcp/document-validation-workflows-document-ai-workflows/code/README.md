# Infrastructure as Code for Document Validation Workflows with Document AI and Cloud Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Document Validation Workflows with Document AI and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Document AI API
  - Cloud Workflows API
  - Cloud Storage API
  - Eventarc API
  - BigQuery API
  - Cloud Build API
- Service account with necessary permissions (automatically created by scripts)

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/doc-validation-deployment \
    --service-account SERVICE_ACCOUNT_EMAIL \
    --local-source="."
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
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
```

### Customizable Parameters

#### Infrastructure Manager
- Edit `main.yaml` to modify resource configurations
- Adjust processor types and bucket names as needed

#### Terraform
- Modify `variables.tf` to customize default values
- Override variables using `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
```

## Architecture Overview

The infrastructure deploys:

1. **Document AI Processors**: Form and Invoice processors for intelligent document extraction
2. **Cloud Storage Buckets**: Input, validation result, and processing buckets
3. **Cloud Workflows**: Orchestration engine for document validation pipeline
4. **Eventarc Triggers**: Event-driven automation for document processing
5. **BigQuery Dataset**: Analytics and reporting for processing metrics
6. **IAM Configuration**: Service accounts and permissions following least privilege

## Post-Deployment Testing

After deployment, test the solution:

1. **Upload a sample document**:
   ```bash
   # Create a test document
   echo "Sample Invoice Document" > test_invoice.txt
   
   # Upload to input bucket
   gsutil cp test_invoice.txt gs://doc-input-[SUFFIX]/
   ```

2. **Monitor workflow execution**:
   ```bash
   # List workflow executions
   gcloud workflows executions list document-validation-workflow \
       --location=${REGION}
   ```

3. **Check processing results**:
   ```bash
   # View processed documents
   gsutil ls gs://doc-valid-[SUFFIX]/
   gsutil ls gs://doc-review-[SUFFIX]/
   gsutil ls gs://doc-invalid-[SUFFIX]/
   ```

4. **Query analytics data**:
   ```bash
   # View processing metrics
   bq query --use_legacy_sql=false "
   SELECT validation_status, COUNT(*) as count
   FROM \`${PROJECT_ID}.document_analytics_*.processing_results\`
   GROUP BY validation_status"
   ```

## Security Considerations

- **IAM Permissions**: Uses least privilege principle with dedicated service accounts
- **Data Encryption**: All storage buckets use Google Cloud default encryption
- **Network Security**: Resources deployed in default VPC with appropriate firewall rules
- **API Security**: Document AI and other APIs secured with proper authentication

## Cost Optimization

- **Document AI**: Charges per document page processed
- **Cloud Workflows**: Pay-per-execution pricing
- **Cloud Storage**: Standard storage class for cost-effective document storage
- **BigQuery**: On-demand pricing for analytics queries

Estimated monthly cost for moderate usage (100 documents/day): $50-150 USD

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Workflow Execution Failures**:
   ```bash
   # Check workflow logs
   gcloud workflows executions describe EXECUTION_ID \
       --workflow=document-validation-workflow \
       --location=${REGION}
   ```

3. **Document Processing Errors**:
   ```bash
   # Verify Document AI processors
   gcloud documentai processors list --location=${REGION}
   ```

### Debugging Steps

1. Check API enablement:
   ```bash
   gcloud services list --enabled
   ```

2. Verify resource creation:
   ```bash
   # Check buckets
   gsutil ls -p ${PROJECT_ID}
   
   # Check workflows
   gcloud workflows list --location=${REGION}
   
   # Check processors
   gcloud documentai processors list --location=${REGION}
   ```

3. Review logs:
   ```bash
   # View Cloud Workflows logs
   gcloud logging read "resource.type=cloud_workflow"
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/doc-validation-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gsutil ls -p ${PROJECT_ID}
gcloud workflows list --location=${REGION}
gcloud documentai processors list --location=${REGION}
bq ls --project_id=${PROJECT_ID}
```

## Monitoring and Observability

### Cloud Monitoring

The solution includes monitoring for:
- Workflow execution success/failure rates
- Document processing latency
- Storage bucket utilization
- API quotas and limits

### Logging

Comprehensive logging is available through:
- Cloud Workflows execution logs
- Document AI processing logs
- Eventarc trigger logs
- BigQuery job logs

### Alerting

Set up alerts for:
- Workflow execution failures
- High processing latency
- Storage quota approaching limits
- Unusual error rates

## Extension Opportunities

1. **Custom Document Types**: Add specialized Document AI processors
2. **Advanced Validation**: Implement custom validation rules
3. **Human Review Interface**: Build web application for manual review
4. **Multi-language Support**: Add translation capabilities
5. **Real-time Dashboard**: Create monitoring and analytics dashboard

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud Documentation for service-specific guidance
3. Verify IAM permissions and API enablement
4. Review Cloud Workflows execution logs for detailed error information

## Version Information

- **Recipe Version**: 1.0
- **Infrastructure Manager**: Compatible with latest Google Cloud APIs
- **Terraform**: Requires version >= 1.0 with Google Cloud provider >= 4.0
- **Google Cloud CLI**: Requires latest version with required APIs enabled

## Related Resources

- [Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Eventarc Documentation](https://cloud.google.com/eventarc/docs)
- [Google Cloud Storage Best Practices](https://cloud.google.com/storage/docs/best-practices)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)