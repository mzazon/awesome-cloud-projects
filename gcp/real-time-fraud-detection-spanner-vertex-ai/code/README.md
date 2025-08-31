# Infrastructure as Code for Real-time Fraud Detection with Spanner and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-time Fraud Detection with Spanner and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Common Requirements

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Required APIs enabled (will be enabled automatically during deployment):
  - Cloud Spanner API
  - Vertex AI API
  - Cloud Functions API
  - Pub/Sub API
  - Cloud Build API
  - Cloud Logging API
- Appropriate IAM permissions for:
  - Spanner Admin
  - Vertex AI User
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Storage Admin
  - Project Editor (or equivalent granular permissions)

### Tool-Specific Prerequisites

#### Infrastructure Manager
- No additional tools required (uses gcloud)

#### Terraform
- Terraform >= 1.5.0 installed
- Google Cloud provider >= 5.0.0

#### Bash Scripts
- Bash shell environment
- `curl` and `openssl` utilities

## Estimated Costs

This infrastructure creates billable resources:
- **Cloud Spanner**: ~$10-30/day (100 processing units)
- **Vertex AI**: ~$5-15/day (model serving and predictions)
- **Cloud Functions**: ~$1-5/day (execution costs)
- **Pub/Sub**: ~$1-3/day (message processing)
- **Cloud Storage**: <$1/day (training data storage)

**Total estimated cost: $20-50/day for development/testing**

> **Warning**: Remember to clean up resources after testing to avoid ongoing charges.

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/fraud-detection \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/real-time-fraud-detection-spanner-vertex-ai/code/infrastructure-manager" \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/fraud-detection
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

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

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud spanner instances describe fraud-detection-instance
gcloud functions describe fraud-detector --region=${REGION} --gen2
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | None | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `SPANNER_INSTANCE` | Spanner instance name | `fraud-detection-instance` | No |
| `DATABASE_NAME` | Spanner database name | `fraud-detection-db` | No |
| `PROCESSING_UNITS` | Spanner processing units | `100` | No |
| `FUNCTION_MEMORY` | Cloud Function memory | `512MB` | No |
| `FUNCTION_TIMEOUT` | Cloud Function timeout | `60s` | No |
| `MAX_INSTANCES` | Function max instances | `10` | No |

### Terraform Variables

The Terraform implementation supports additional customization through variables:

```bash
# Example with custom configuration
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-west1" \
    -var="spanner_processing_units=200" \
    -var="function_memory=1024" \
    -var="environment=production"
```

See `terraform/variables.tf` for all available options.

## Validation

After deployment, verify the infrastructure:

### Check Spanner Instance and Database

```bash
# Verify Spanner instance
gcloud spanner instances describe ${SPANNER_INSTANCE:-fraud-detection-instance}

# Check database schema
gcloud spanner databases execute-sql ${DATABASE_NAME:-fraud-detection-db} \
    --instance=${SPANNER_INSTANCE:-fraud-detection-instance} \
    --sql="SELECT table_name FROM information_schema.tables WHERE table_schema = ''"
```

### Test Cloud Function

```bash
# Check function deployment
gcloud functions describe fraud-detector \
    --region=${REGION:-us-central1} \
    --gen2

# Test with sample transaction
TOPIC_NAME=$(gcloud pubsub topics list --filter="name:transaction-events" --format="value(name.basename())")
echo '{"transaction_id":"test-123","user_id":"user-1","amount":"150.00","currency":"USD","merchant_id":"test-merchant"}' | \
    gcloud pubsub topics publish ${TOPIC_NAME} --message=-
```

### Verify Pub/Sub Resources

```bash
# List topics and subscriptions
gcloud pubsub topics list --filter="name:transaction-events"
gcloud pubsub subscriptions list --filter="name:fraud-processing"
```

## Monitoring and Logs

### Cloud Function Logs

```bash
# View function execution logs
gcloud functions logs read fraud-detector \
    --gen2 \
    --region=${REGION:-us-central1} \
    --limit=20
```

### Spanner Metrics

```bash
# Check Spanner operations
gcloud spanner operations list \
    --instance=${SPANNER_INSTANCE:-fraud-detection-instance}
```

### Pub/Sub Monitoring

```bash
# Check message processing
gcloud pubsub topics list-subscriptions \
    transaction-events-$(date +%s | tail -c 4)
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services enable spanner.googleapis.com aiplatform.googleapis.com cloudfunctions.googleapis.com pubsub.googleapis.com
   ```

2. **IAM Permissions**: Verify your account has required permissions
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Function Deployment Failure**: Check Cloud Build logs
   ```bash
   gcloud builds list --limit=5
   ```

4. **Spanner Connection Issues**: Verify network and firewall settings
   ```bash
   gcloud compute firewall-rules list
   ```

### Resource State Verification

```bash
# Check all created resources
gcloud spanner instances list
gcloud functions list --gen2
gcloud pubsub topics list
gcloud storage buckets list --filter="name:*fraud-detection*"
```

## Cleanup

> **Warning**: Cleanup operations will permanently delete all resources and data. Ensure you have backups if needed.

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/fraud-detection
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Spanner resources
gcloud spanner databases delete fraud-detection-db --instance=fraud-detection-instance --quiet
gcloud spanner instances delete fraud-detection-instance --quiet

# Delete Cloud Functions
gcloud functions delete fraud-detector --region=${REGION:-us-central1} --gen2 --quiet

# Delete Pub/Sub resources
TOPIC_NAME=$(gcloud pubsub topics list --filter="name:transaction-events" --format="value(name.basename())" | head -1)
SUBSCRIPTION_NAME=$(gcloud pubsub subscriptions list --filter="name:fraud-processing" --format="value(name.basename())" | head -1)
gcloud pubsub subscriptions delete ${SUBSCRIPTION_NAME} --quiet
gcloud pubsub topics delete ${TOPIC_NAME} --quiet

# Delete Cloud Storage buckets
gsutil -m rm -r gs://${PROJECT_ID}-fraud-detection-data
```

## Customization

### Modifying Spanner Configuration

To change Spanner instance configuration, update the following:

**Terraform**: Edit `terraform/main.tf`
```hcl
resource "google_spanner_instance" "fraud_detection" {
  config           = "nam6"  # Change region configuration
  processing_units = 200     # Increase processing units
}
```

**Infrastructure Manager**: Edit `infrastructure-manager/main.yaml`
```yaml
resources:
- name: fraud-detection-instance
  type: gcp-types/spanner-v1:projects.instances
  properties:
    config: projects/${PROJECT_ID}/instanceConfigs/nam6
    processingUnits: 200
```

### Adding Custom Function Code

The Cloud Function source code can be customized by:

1. Modifying the function code in the respective IaC templates
2. Adding environment variables for external service integration
3. Updating IAM permissions for additional Google Cloud services

### Scaling Configuration

Adjust scaling parameters in the IaC templates:

- **Spanner**: Processing units and node count
- **Cloud Functions**: Memory, timeout, and max instances
- **Pub/Sub**: Message retention and acknowledgment settings

## Security Considerations

This infrastructure implements several security best practices:

- **IAM**: Least privilege access for all service accounts
- **Encryption**: Data encrypted at rest and in transit
- **Network**: Private Google access where appropriate
- **Audit**: Cloud Audit Logs enabled for all services

### Additional Security Enhancements

For production deployments, consider:

1. **VPC Service Controls**: Isolate resources in security perimeters
2. **Private Endpoints**: Use private connectivity for all services
3. **Key Management**: Use Customer Managed Encryption Keys (CMEK)
4. **Binary Authorization**: Secure container image deployment
5. **Security Command Center**: Centralized security monitoring

## Performance Optimization

### Spanner Optimization

- Monitor CPU utilization and scale processing units as needed
- Use secondary indexes for complex fraud detection queries
- Consider regional vs. multi-regional configuration based on latency requirements

### Function Optimization

- Adjust memory allocation based on processing requirements
- Use connection pooling for Spanner client connections
- Implement caching for frequently accessed data

### Pub/Sub Optimization

- Tune acknowledgment deadlines based on processing time
- Use push vs. pull subscriptions based on traffic patterns
- Configure message ordering if sequence is important

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../real-time-fraud-detection-spanner-vertex-ai.md)
2. Review Google Cloud documentation:
   - [Cloud Spanner Documentation](https://cloud.google.com/spanner/docs)
   - [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
   - [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
   - [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
3. Check Google Cloud Status page for service issues
4. Contact Google Cloud Support for infrastructure-specific problems

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation for any new variables or outputs
3. Follow Google Cloud best practices and security guidelines
4. Validate all IaC templates before committing changes