# Infrastructure as Code for Time Zone Converter API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Time Zone Converter API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions deployment
  - Cloud Build API access
  - IAM policy binding
- For Terraform: Terraform CLI installed (version >= 1.5.0)
- For Infrastructure Manager: Infrastructure Manager API enabled

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/timezone-converter \
    --service-account PROJECT_ID@appspot.gserviceaccount.com \
    --git-source-repo="https://source.developers.google.com/p/PROJECT_ID/r/REPO_NAME" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=PROJECT_ID,region=us-central1"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Get the function URL
terraform output function_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="timezone-converter"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the function URL upon successful deployment
```

## Configuration Options

### Common Variables

All implementations support these configuration options:

- **project_id**: Your Google Cloud project ID
- **region**: GCP region for resource deployment (default: us-central1)
- **function_name**: Name for the Cloud Function (default: timezone-converter)
- **memory**: Memory allocation for the function (default: 256MB)
- **timeout**: Function timeout in seconds (default: 60s)
- **min_instances**: Minimum number of function instances (default: 0)
- **max_instances**: Maximum number of function instances (default: 100)

### Infrastructure Manager Variables

Specify variables in your deployment command:

```bash
--input-values="project_id=my-project,region=us-west1,function_name=my-timezone-api"
```

### Terraform Variables

Set variables via command line:

```bash
terraform apply \
  -var="project_id=my-project" \
  -var="region=us-west1" \
  -var="function_name=my-timezone-api" \
  -var="memory=512MB"
```

Or create a `terraform.tfvars` file:

```hcl
project_id    = "my-project"
region        = "us-west1"
function_name = "my-timezone-api"
memory        = "512MB"
timeout       = "120s"
```

### Bash Script Variables

Set environment variables before running:

```bash
export PROJECT_ID="my-project"
export REGION="us-west1"
export FUNCTION_NAME="my-timezone-api"
export MEMORY="512MB"
export TIMEOUT="120s"
```

## Outputs

All implementations provide these outputs:

- **function_url**: The HTTPS URL for invoking the Cloud Function
- **function_name**: The deployed function name
- **project_id**: The GCP project ID used
- **region**: The deployment region

## Testing the Deployment

Once deployed, test your timezone converter API:

```bash
# Get current time conversion (using function URL from outputs)
curl "https://REGION-PROJECT_ID.cloudfunctions.net/FUNCTION_NAME?from_timezone=America/New_York&to_timezone=Europe/London"

# Convert specific timestamp
curl -X POST "https://REGION-PROJECT_ID.cloudfunctions.net/FUNCTION_NAME" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2024-06-15T14:30:00",
    "from_timezone": "America/Los_Angeles",
    "to_timezone": "Asia/Tokyo"
  }'

# Test error handling
curl "https://REGION-PROJECT_ID.cloudfunctions.net/FUNCTION_NAME?from_timezone=Invalid/Zone&to_timezone=UTC"
```

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/timezone-converter
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Monitoring and Observability

The deployed function automatically integrates with Google Cloud's observability stack:

- **Cloud Logging**: Function execution logs are available in Cloud Logging
- **Cloud Monitoring**: Metrics for invocations, duration, and errors
- **Error Reporting**: Automatic error detection and reporting

Access monitoring data:

```bash
# View function logs
gcloud functions logs read FUNCTION_NAME --region=REGION

# Get function metrics
gcloud monitoring metrics list --filter="resource.type=cloud_function"
```

## Security Considerations

The infrastructure implements these security best practices:

- **Public Access**: Function allows unauthenticated access for API usage
- **CORS**: Proper CORS headers for web browser compatibility
- **Input Validation**: Comprehensive input validation and error handling
- **Least Privilege**: Function runs with minimal required permissions

To restrict access, modify the IAM bindings:

```bash
# Remove public access
gcloud functions remove-iam-policy-binding FUNCTION_NAME \
  --region=REGION \
  --member="allUsers" \
  --role="roles/cloudfunctions.invoker"

# Add specific user access
gcloud functions add-iam-policy-binding FUNCTION_NAME \
  --region=REGION \
  --member="user:specific-user@example.com" \
  --role="roles/cloudfunctions.invoker"
```

## Cost Optimization

Cloud Functions pricing is based on:

- **Invocations**: First 2 million requests per month are free
- **Compute Time**: Charged per 100ms increments based on allocated memory
- **Networking**: Egress charges for responses (minimal for this API)

For cost optimization:

1. **Monitor Usage**: Use Cloud Monitoring to track invocation patterns
2. **Adjust Memory**: Start with 256MB and adjust based on performance needs
3. **Set Concurrency**: Configure max instances to control concurrent costs
4. **Enable Caching**: Implement client-side caching for frequently requested conversions

Estimated monthly costs for typical usage:
- Light usage (< 100K requests): $0.00 (within free tier)
- Medium usage (1M requests): ~$0.40
- Heavy usage (10M requests): ~$4.00

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**
   ```bash
   # Check enabled APIs
   gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com OR name:cloudbuild.googleapis.com"
   
   # Enable if missing
   gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com
   ```

2. **Permission Denied Errors**
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy PROJECT_ID
   
   # Ensure your account has Cloud Functions Admin role
   gcloud projects add-iam-policy-binding PROJECT_ID \
     --member="user:your-email@example.com" \
     --role="roles/cloudfunctions.admin"
   ```

3. **Function Returns 500 Errors**
   ```bash
   # Check function logs
   gcloud functions logs read FUNCTION_NAME --region=REGION --limit=50
   ```

4. **Terraform State Issues**
   ```bash
   # Refresh Terraform state
   terraform refresh
   
   # Import existing resources if needed
   terraform import google_cloudfunctions2_function.timezone_converter projects/PROJECT_ID/locations/REGION/functions/FUNCTION_NAME
   ```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# For bash scripts
export DEBUG=true
./scripts/deploy.sh

# For gcloud commands
export CLOUDSDK_CORE_VERBOSITY=debug
gcloud functions deploy ...
```

## Advanced Configuration

### Custom Runtime Configuration

Modify the function configuration for specific requirements:

```bash
# Deploy with custom environment variables
gcloud functions deploy FUNCTION_NAME \
  --gen2 \
  --runtime python312 \
  --trigger-http \
  --entry-point convert_timezone \
  --region REGION \
  --memory 512MB \
  --timeout 120s \
  --set-env-vars "TZ_DEFAULT=UTC,LOG_LEVEL=DEBUG" \
  --max-instances 50 \
  --min-instances 1
```

### VPC Integration

To deploy within a VPC for enhanced security:

```bash
# Deploy with VPC connector
gcloud functions deploy FUNCTION_NAME \
  --gen2 \
  --runtime python312 \
  --trigger-http \
  --entry-point convert_timezone \
  --region REGION \
  --vpc-connector projects/PROJECT_ID/locations/REGION/connectors/CONNECTOR_NAME \
  --egress-settings private-ranges-only
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe at `../timezone-converter-api-functions.md`
2. **Google Cloud Documentation**: 
   - [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Documentation**: [Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: 
   - [Google Cloud Community](https://cloud.google.com/community)
   - [Stack Overflow - google-cloud-functions](https://stackoverflow.com/questions/tagged/google-cloud-functions)

## Contributing

To improve this infrastructure code:

1. Test changes thoroughly in a development environment
2. Validate with both Infrastructure Manager and Terraform
3. Update documentation for any new variables or outputs
4. Follow Google Cloud best practices and security guidelines