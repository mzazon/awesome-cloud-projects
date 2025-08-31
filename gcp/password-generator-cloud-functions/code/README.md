# Infrastructure as Code for Simple Password Generator with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Password Generator with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate permissions for resource creation:
  - Cloud Functions Admin
  - Cloud Build Editor
  - Service Account User
  - Project IAM Admin (for service account creation)
- APIs enabled:
  - Cloud Functions API
  - Cloud Build API
  - Cloud Run API (required for 2nd gen functions)

## Quick Start

### Using Infrastructure Manager

```bash
# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/password-generator \
    --service-account=$SERVICE_ACCOUNT_EMAIL \
    --local-source=infrastructure-manager/ \
    --inputs-file=infrastructure-manager/inputs.yaml
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform with Google Cloud provider
terraform init

# Review planned infrastructure changes
terraform plan -var="project_id=$PROJECT_ID" -var="region=$REGION"

# Deploy the infrastructure
terraform apply -var="project_id=$PROJECT_ID" -var="region=$REGION"

# Get the function URL from outputs
terraform output function_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the password generator function
./scripts/deploy.sh

# The script will prompt for required variables or use environment variables:
# - PROJECT_ID: Your Google Cloud Project ID
# - REGION: Deployment region (default: us-central1)
# - FUNCTION_NAME: Cloud Function name (default: password-generator)
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml` to customize:

```yaml
project_id: "your-project-id"
region: "us-central1"
function_name: "password-generator"
function_memory: "256Mi"
function_timeout: "60s"
max_instances: 10
allow_unauthenticated: true
```

### Terraform Variables

Set variables in `terraform.tfvars` or pass via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "password-generator"
function_memory = "256Mi"
function_timeout = "60s"
max_instances = 10
allow_unauthenticated = true
```

### Bash Script Environment Variables

Set these environment variables before running the deployment script:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="password-generator"
```

## Testing the Deployed Function

After deployment, test the password generator function:

```bash
# Get the function URL (from Terraform output or Infrastructure Manager)
FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME \
    --gen2 \
    --region=$REGION \
    --format="value(serviceConfig.uri)")

# Test basic password generation
curl -X GET "$FUNCTION_URL?length=16" | jq '.'

# Test with custom parameters
curl -X GET "$FUNCTION_URL?length=20&include_symbols=true" | jq '.'

# Test with POST request
curl -X POST "$FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d '{"length": 14, "include_symbols": false}' | jq '.'
```

Expected response format:
```json
{
  "password": "Xy7#mK9@nP2$qW8!",
  "length": 16,
  "character_types": {
    "lowercase": true,
    "uppercase": true,
    "numbers": true,
    "symbols": true
  },
  "entropy_bits": 95.27,
  "charset_size": 94
}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/password-generator
```

### Using Terraform

```bash
cd terraform/

# Destroy all created resources
terraform destroy -var="project_id=$PROJECT_ID" -var="region=$REGION"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will remove:
# - Cloud Function
# - Associated IAM bindings
# - Cloud Build artifacts (optional)
```

## Security Considerations

### Authentication and Access Control

By default, the function is deployed with `--allow-unauthenticated` for testing purposes. For production deployments:

1. **Remove unauthenticated access**:
   ```bash
   gcloud functions remove-iam-policy-binding $FUNCTION_NAME \
       --gen2 \
       --region=$REGION \
       --member="allUsers" \
       --role="roles/cloudfunctions.invoker"
   ```

2. **Add specific user or service account access**:
   ```bash
   gcloud functions add-iam-policy-binding $FUNCTION_NAME \
       --gen2 \
       --region=$REGION \
       --member="user:your-email@example.com" \
       --role="roles/cloudfunctions.invoker"
   ```

3. **Use API Gateway or Cloud Endpoints** for additional security features like API keys, rate limiting, and authentication.

### Network Security

- The function uses HTTPS by default
- Consider VPC connector for private network access
- Implement IP allowlisting if needed through Cloud Armor

## Monitoring and Observability

### Cloud Logging

View function logs:
```bash
gcloud functions logs read $FUNCTION_NAME \
    --gen2 \
    --region=$REGION \
    --limit=50
```

### Cloud Monitoring

Set up monitoring dashboards and alerts:
- Function invocation count
- Function execution time
- Error rate
- Memory and CPU usage

### Sample Monitoring Query

```sql
resource.type="cloud_function"
resource.labels.function_name="password-generator"
severity>=ERROR
```

## Cost Optimization

### Free Tier Limits

Google Cloud Functions free tier includes:
- 2 million invocations per month
- 400,000 GB-seconds of compute time
- 200,000 GHz-seconds of compute time

### Cost Monitoring

- Set up budget alerts in Cloud Billing
- Monitor usage in Cloud Monitoring
- Consider implementing client-side caching for frequently requested password configurations

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify required APIs are enabled
   - Check IAM permissions
   - Ensure project billing is enabled

2. **Function returns 403 Forbidden**:
   - Verify IAM invoker permissions
   - Check if `--allow-unauthenticated` is set correctly

3. **Function times out**:
   - Check function timeout settings (default: 60s)
   - Review function logs for performance issues

4. **CORS errors in browser**:
   - Verify CORS headers are properly set in function code
   - Test with curl to isolate browser-specific issues

### Debug Mode

Enable debug logging by setting environment variables:
```bash
export FUNCTION_DEBUG=true
```

## Customization

### Extending the Password Generator

1. **Add password policies**: Modify the function to support predefined security policies
2. **Integrate with Secret Manager**: Store generated passwords securely
3. **Add audit logging**: Log password generation events (without storing actual passwords)
4. **Implement rate limiting**: Add request throttling for production use

### Infrastructure Customization

Modify the IaC templates to:
- Change function runtime (Python 3.9, 3.10, 3.11)
- Adjust memory allocation (128Mi to 8Gi)
- Configure VPC connectivity
- Add custom environment variables
- Set up CI/CD integration

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation in `../password-generator-cloud-functions.md`
2. Review Google Cloud Functions documentation: https://cloud.google.com/functions/docs
3. Consult Google Cloud Infrastructure Manager documentation: https://cloud.google.com/infrastructure-manager/docs
4. Reference Terraform Google Cloud Provider documentation: https://registry.terraform.io/providers/hashicorp/google/latest/docs