# Infrastructure as Code for Automated Solar Assessment with Solar API and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Solar Assessment with Solar API and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud Project with billing enabled
- Project Owner or Editor permissions for resource creation
- Maps Platform Solar API enabled and configured
- Google Maps Platform API key with Solar API access

### Required APIs

```bash
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable solar.googleapis.com
```

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create solar-assessment-deployment \
    --location=${REGION} \
    --source=infrastructure-manager/main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Check deployment status
gcloud infra-manager deployments describe solar-assessment-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

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

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud functions list --filter="name:solar-processor"
gsutil ls -p ${PROJECT_ID}
```

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage Buckets**: Input and output buckets for CSV processing
- **Cloud Function**: Serverless function for solar assessment processing
- **IAM Service Account**: Dedicated service account with minimal required permissions
- **API Key**: Google Maps Platform API key with Solar API access
- **Event Trigger**: Cloud Storage trigger to invoke function on file upload

## Configuration Variables

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `solar-processor` | No |
| `input_bucket_name` | Input bucket name | `solar-input-${random}` | No |
| `output_bucket_name` | Output bucket name | `solar-results-${random}` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Compute zone | `us-central1-a` | No |
| `function_memory` | Function memory allocation | `512Mi` | No |
| `function_timeout` | Function timeout in seconds | `540` | No |
| `api_key_name` | Solar API key name | `solar-assessment-key` | No |

## Testing the Deployment

1. **Create sample data file**:

```bash
cat > sample_properties.csv << 'EOF'
address,latitude,longitude
"1600 Amphitheatre Pkwy, Mountain View, CA",37.4220041,-122.0862515
"One Apple Park Way, Cupertino, CA",37.3348274,-122.0090531
"1 Tesla Rd, Austin, TX",30.2711286,-97.7436995
EOF
```

2. **Upload test file**:

```bash
# Get input bucket name
INPUT_BUCKET=$(terraform output -raw input_bucket_name 2>/dev/null || gcloud storage buckets list --filter="name:solar-input" --format="value(name)")

# Upload test file
gsutil cp sample_properties.csv gs://${INPUT_BUCKET}/
```

3. **Monitor function execution**:

```bash
# View function logs
gcloud functions logs read solar-processor \
    --region=${REGION} \
    --limit=20

# Check output bucket for results
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name 2>/dev/null || gcloud storage buckets list --filter="name:solar-results" --format="value(name)")
gsutil ls gs://${OUTPUT_BUCKET}/
```

## Cost Considerations

### Estimated Monthly Costs (100 assessments)

- **Cloud Functions**: $0.01-0.05 (minimal execution time)
- **Cloud Storage**: $0.02-0.05 (1GB storage)
- **Solar API**: $1.00-2.00 ($0.01-0.02 per request)
- **Total**: $1.03-2.10 per month

### Cost Optimization Tips

- Use Cloud Storage lifecycle policies for result data
- Configure function memory based on actual usage
- Monitor Solar API usage to avoid unexpected charges
- Implement batch processing for large property lists

## Security Features

### IAM Configuration

- **Principle of Least Privilege**: Service account has minimal required permissions
- **Resource-Level Access**: Permissions scoped to specific buckets and functions
- **API Key Restrictions**: Solar API key restricted to Solar API endpoints only

### Data Protection

- **Bucket Versioning**: Enabled on both input and output buckets
- **Secure Transmission**: All API calls use HTTPS
- **Access Logging**: Cloud Audit Logs track all resource access

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete solar-assessment-deployment \
    --location=${REGION}

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform state list
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud functions list --filter="name:solar-processor"
gcloud storage buckets list --filter="name:solar-"
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud functions delete solar-processor --region=${REGION} --quiet
gsutil -m rm -r gs://solar-input-* gs://solar-results-*
gcloud services api-keys delete solar-assessment-key --location=global --quiet
```

## Troubleshooting

### Common Issues

1. **API Key Permissions**:
   ```bash
   # Verify Solar API is enabled
   gcloud services list --enabled --filter="name:solar.googleapis.com"
   
   # Check API key restrictions
   gcloud services api-keys describe solar-assessment-key --location=global
   ```

2. **Function Deployment Failures**:
   ```bash
   # Check function deployment logs
   gcloud functions logs read solar-processor --region=${REGION}
   
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Storage Access Issues**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://solar-input-bucket-name
   gsutil iam get gs://solar-results-bucket-name
   ```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Set debug environment variable
export TF_LOG=DEBUG  # For Terraform
export CLOUDSDK_CORE_VERBOSITY=debug  # For gcloud commands

# Deploy with debug logging
./scripts/deploy.sh
```

## Customization

### Extending Function Capabilities

1. **Add BigQuery Integration**: Modify function to store results in BigQuery for analytics
2. **Implement Batch Optimization**: Process multiple properties in single API calls
3. **Add Notification System**: Integrate with Pub/Sub for processing notifications
4. **Enhanced Error Handling**: Implement retry logic and dead letter queues

### Regional Deployment

```bash
# Deploy to multiple regions
export REGIONS="us-central1 us-east1 europe-west1"

for region in $REGIONS; do
    terraform workspace new $region || terraform workspace select $region
    terraform apply -var="region=$region"
done
```

### Production Considerations

- Implement Cloud Monitoring alerts for function failures
- Set up Cloud Logging sinks for long-term log retention
- Configure VPC Service Controls for enhanced security
- Implement Infrastructure Manager or Terraform remote state

## Support

### Documentation Links

- [Google Maps Platform Solar API](https://developers.google.com/maps/documentation/solar)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Storage Best Practices](https://cloud.google.com/storage/docs/best-practices)
- [Infrastructure Manager Guide](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the [original recipe documentation](../automated-solar-assessment-maps-functions.md)
2. Review Google Cloud [troubleshooting guides](https://cloud.google.com/support/docs)
3. Consult [Google Cloud Community](https://cloud.google.com/community)
4. Check [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform) for common issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate with `terraform plan` or Infrastructure Manager preview
3. Update this README with any configuration changes
4. Follow Google Cloud security best practices