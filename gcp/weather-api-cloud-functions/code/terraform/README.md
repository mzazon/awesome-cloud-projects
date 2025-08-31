# Weather API with Cloud Functions - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless weather API using Google Cloud Functions. The infrastructure creates a complete serverless solution with proper IAM, monitoring, and security configurations.

## Architecture Overview

The Terraform configuration deploys:

- **Google Cloud Function (Gen2)**: Serverless HTTP endpoint for the weather API
- **Cloud Storage Bucket**: Stores the function source code archives
- **Service Account**: Dedicated service account with minimal required permissions
- **IAM Policies**: Public access configuration for the HTTP function
- **API Services**: Enables required Google Cloud APIs
- **Monitoring**: Optional log-based metrics for observability

## Prerequisites

### Required Tools

- **Terraform**: Version 1.5 or later
- **Google Cloud CLI**: Latest version
- **Git**: For cloning and version control
- **curl** or **jq**: For testing the deployed API

### Google Cloud Setup

1. **Google Cloud Account**: Active account with billing enabled
2. **Project**: Existing project or create a new one
3. **Authentication**: One of the following:
   ```bash
   # Option 1: Application Default Credentials (recommended for development)
   gcloud auth application-default login
   
   # Option 2: Service Account Key (recommended for CI/CD)
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
   ```

4. **Required APIs**: The Terraform configuration will automatically enable:
   - Cloud Functions API
   - Cloud Build API
   - Artifact Registry API
   - Cloud Logging API
   - Cloud Run API

### Required Permissions

Your account or service account needs these IAM roles:
- `roles/cloudfunctions.admin`
- `roles/storage.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/logging.admin`

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the Terraform directory
cd gcp/weather-api-cloud-functions/code/terraform/
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your project details
nano terraform.tfvars
```

**Minimum required configuration:**
```hcl
project_id = "your-gcp-project-id"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the API

After deployment, Terraform will output the function URL. Test it:

```bash
# Basic test
curl -s "https://REGION-PROJECT_ID.cloudfunctions.net/weather-api"

# Test with city parameter
curl -s "https://REGION-PROJECT_ID.cloudfunctions.net/weather-api?city=Tokyo" | jq .

# Test CORS
curl -s -H "Origin: https://example.com" "https://REGION-PROJECT_ID.cloudfunctions.net/weather-api"
```

## Configuration Options

### Basic Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | ✅ |
| `region` | Deployment region | `us-central1` | ❌ |
| `environment` | Environment label | `development` | ❌ |
| `function_name` | Function name | `weather-api` | ❌ |

### Performance Tuning

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `memory_mb` | Function memory | `256M` | `128M` to `32768M` |
| `timeout_seconds` | Max execution time | `60` | `1` to `3600` |
| `max_instance_count` | Max concurrent instances | `100` | `1` to `3000` |
| `min_instance_count` | Min warm instances | `0` | `0` to `1000` |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `allow_unauthenticated` | Public access | `true` |
| `cors_origins` | Allowed CORS origins | `["*"]` |
| `ingress_settings` | Traffic restrictions | `ALLOW_ALL` |

## Advanced Usage

### Environment-Specific Deployments

Create separate variable files for different environments:

```bash
# Development
terraform apply -var-file="environments/dev.tfvars"

# Staging  
terraform apply -var-file="environments/staging.tfvars"

# Production
terraform apply -var-file="environments/prod.tfvars"
```

### Multi-Region Deployment

Deploy to multiple regions for global availability:

```bash
# US region
terraform apply -var="region=us-central1" -var="function_name=weather-api-us"

# EU region
terraform apply -var="region=europe-west1" -var="function_name=weather-api-eu"

# Asia region
terraform apply -var="region=asia-east1" -var="function_name=weather-api-asia"
```

### Custom Service Account

Use an existing service account instead of creating a new one:

```hcl
service_account_email = "existing-sa@project.iam.gserviceaccount.com"
```

### VPC Integration

Connect the function to a VPC for private resource access:

```hcl
vpc_connector = "projects/PROJECT_ID/locations/REGION/connectors/my-connector"
```

## Monitoring and Observability

### Built-in Monitoring

The configuration creates log-based metrics when `enable_monitoring = true`:

- **Function Errors**: Tracks error rate and types
- **Function Invocations**: Monitors request volume

### Viewing Logs

```bash
# View function logs
gcloud functions logs read weather-api --region=us-central1 --gen2

# Follow logs in real-time
gcloud functions logs tail weather-api --region=us-central1 --gen2
```

### Google Cloud Console

Access monitoring dashboards:
- **Functions**: [Cloud Functions Console](https://console.cloud.google.com/functions)
- **Logs**: [Cloud Logging Console](https://console.cloud.google.com/logs)
- **Metrics**: [Cloud Monitoring Console](https://console.cloud.google.com/monitoring)

## Security Best Practices

### Production Security Checklist

- [ ] **Authentication**: Implement proper authentication instead of public access
- [ ] **CORS**: Use specific origins instead of wildcard (`*`)
- [ ] **API Keys**: Store sensitive data in Secret Manager
- [ ] **IAM**: Follow principle of least privilege
- [ ] **VPC**: Use VPC connectors for private resource access
- [ ] **Audit**: Enable Cloud Audit Logs
- [ ] **Updates**: Keep runtime and dependencies updated

### Secure Configuration Example

```hcl
# Production security settings
allow_unauthenticated = false
cors_origins = ["https://myapp.com", "https://www.myapp.com"]
ingress_settings = "ALLOW_INTERNAL_AND_GCLB"
environment_variables = {
  WEATHER_API_KEY = "projects/PROJECT_ID/secrets/weather-api-key/versions/latest"
}
```

## Troubleshooting

### Common Issues

**1. Permission Denied**
```bash
# Check your authentication
gcloud auth list
gcloud config get-value project

# Verify IAM roles
gcloud projects get-iam-policy PROJECT_ID
```

**2. API Not Enabled**
```bash
# Check enabled APIs
gcloud services list --enabled

# Enable missing APIs
gcloud services enable cloudfunctions.googleapis.com
```

**3. Function Not Responding**
```bash
# Check function status
gcloud functions describe weather-api --region=us-central1 --gen2

# View recent logs
gcloud functions logs read weather-api --region=us-central1 --gen2 --limit=50
```

**4. Terraform State Issues**
```bash
# Refresh state
terraform refresh

# Import existing resources (if needed)
terraform import google_cloudfunctions2_function.weather_api projects/PROJECT_ID/locations/REGION/functions/FUNCTION_NAME
```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
export TF_LOG=DEBUG
terraform apply
```

## Cost Optimization

### Free Tier Limits

Google Cloud Functions provides generous free tier limits:
- **2 million invocations** per month
- **400,000 GB-seconds** of compute time
- **200,000 GHz-seconds** of CPU time
- **5 GB** of Internet egress

### Cost Optimization Tips

1. **Right-size Memory**: Don't over-allocate memory
2. **Minimize Cold Starts**: Set `min_instance_count > 0` only if needed
3. **Optimize Timeout**: Use shorter timeouts to prevent runaway costs
4. **Monitor Usage**: Enable monitoring to track actual usage
5. **Regional Deployment**: Choose regions close to users

### Cost Estimation

```bash
# View current month usage
gcloud billing budgets list

# Estimate costs based on traffic
# Example: 100,000 requests/month with 256MB memory
# Cost ≈ $0.50-$2.00/month (well within free tier)
```

## Migration and Updates

### Updating Function Code

1. **Modify Source**: Update files in `function_source/`
2. **Apply Changes**: Run `terraform apply`
3. **Test**: Verify the updated function works correctly

### Runtime Updates

```hcl
# Update Python runtime version
function_runtime = "python313"  # Latest supported version
```

### Terraform State Migration

For major infrastructure changes:

```bash
# Backup current state
terraform state pull > terraform.tfstate.backup

# Plan migration
terraform plan -out=migration.tfplan

# Apply with backup ready
terraform apply migration.tfplan
```

## Extending the Solution

### Real Weather API Integration

Replace mock data with real weather services:

1. **Get API Key**: Sign up for OpenWeatherMap, AccuWeather, etc.
2. **Store Securely**: Use Secret Manager for API keys
3. **Update Code**: Modify `function_source/main.py` to call real APIs
4. **Handle Errors**: Implement retry logic and circuit breakers

### Add Authentication

Implement API key authentication:

```python
# Add to main.py
def validate_api_key(request):
    api_key = request.headers.get('X-API-Key')
    if not api_key or api_key != os.environ.get('VALID_API_KEY'):
        return False
    return True
```

### Database Integration

Add data persistence with Firestore:

```hcl
# Add to main.tf
resource "google_firestore_database" "weather_cache" {
  name     = "(default)"
  type     = "FIRESTORE_NATIVE"
  location = var.region
}
```

### Load Balancing

Add global load balancing for multi-region deployment:

```hcl
resource "google_compute_global_address" "weather_api" {
  name = "weather-api-ip"
}

resource "google_compute_global_forwarding_rule" "weather_api" {
  name       = "weather-api-forwarding-rule"
  target     = google_compute_target_https_proxy.weather_api.id
  ip_address = google_compute_global_address.weather_api.address
  port_range = "443"
}
```

## Cleanup

### Destroy Infrastructure

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

### Manual Cleanup

If automatic cleanup fails:

```bash
# Delete function
gcloud functions delete weather-api --region=us-central1 --gen2

# Delete storage bucket
gsutil rm -r gs://PROJECT_ID-weather-api-source

# Delete service account
gcloud iam service-accounts delete weather-api-sa@PROJECT_ID.iam.gserviceaccount.com
```

## Support and Resources

### Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Functions Python Runtime](https://cloud.google.com/functions/docs/concepts/python-runtime)

### Community

- [Google Cloud Community](https://www.googlecloudcommunity.com/)
- [Terraform Community](https://discuss.hashicorp.com/c/terraform-core)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-functions)

### Professional Support

- [Google Cloud Support](https://cloud.google.com/support)
- [HashiCorp Support](https://www.hashicorp.com/support)

## License

This infrastructure code is provided under the Apache 2.0 License. See the recipe documentation for complete terms and conditions.