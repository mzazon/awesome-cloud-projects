# URL Shortener Infrastructure as Code

This Terraform module deploys a serverless URL shortening service on Google Cloud Platform using Cloud Functions and Firestore.

## Overview

The URL shortener consists of:

- **Cloud Functions (2nd Gen)**: Serverless HTTP function for URL shortening and redirection
- **Firestore Database**: NoSQL document database for storing URL mappings
- **Cloud Storage**: Bucket for storing function source code
- **IAM Service Account**: Dedicated service account with minimal required permissions

## Architecture

```
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   Web Client    │────│   Cloud Function     │────│   Firestore     │
│                 │    │   (HTTP Trigger)     │    │   Database      │
└─────────────────┘    └──────────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ Cloud Storage   │
                       │ (Source Code)   │
                       └─────────────────┘
```

## Features

- **URL Shortening**: Convert long URLs into short, shareable links
- **URL Redirection**: Automatic 301 redirects to original URLs
- **Click Tracking**: Track click counts and access metadata
- **Statistics API**: Get analytics for shortened URLs
- **Health Checks**: Built-in health monitoring endpoint
- **CORS Support**: Configurable Cross-Origin Resource Sharing
- **Security**: IAM-based access control and Firestore security rules

## Prerequisites

1. **Google Cloud Project**: Active GCP project with billing enabled
2. **Terraform**: Version 1.5.0 or later
3. **gcloud CLI**: Authenticated and configured (optional, for manual operations)
4. **Required APIs**: The following APIs will be automatically enabled:
   - Cloud Functions API
   - Firestore API
   - Cloud Build API
   - Cloud Storage API
   - Cloud Resource Manager API

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd gcp/url-shortener-functions-firestore/code/terraform/

# Copy terraform.tfvars.example (if provided) or create your own
cp terraform.tfvars.example terraform.tfvars
```

### 2. Set Required Variables

Create a `terraform.tfvars` file:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
function_name = "url-shortener"
function_memory = "256M"
allow_unauthenticated_access = true

resource_labels = {
  application = "url-shortener"
  environment = "production"
  managed-by  = "terraform"
}
```

### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the Deployment

After deployment, use the function URL from outputs:

```bash
# Get the function URL
FUNCTION_URL=$(terraform output -raw function_url)

# Test URL shortening
curl -X POST $FUNCTION_URL/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://cloud.google.com"}'

# Test redirection (replace ABC123 with actual short ID)
curl -I $FUNCTION_URL/ABC123

# Check health
curl $FUNCTION_URL/health
```

## Configuration

### Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `project_id` | Google Cloud project ID | `string` |

### Optional Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `region` | GCP region for deployment | `us-central1` | `string` |
| `function_name` | Cloud Function name | `url-shortener` | `string` |
| `function_memory` | Memory allocation | `256M` | `string` |
| `function_timeout` | Function timeout (seconds) | `60` | `number` |
| `function_max_instances` | Maximum instances | `10` | `number` |
| `function_min_instances` | Minimum instances | `0` | `number` |
| `firestore_location` | Firestore location | `nam5` | `string` |
| `allow_unauthenticated_access` | Allow public access | `true` | `bool` |
| `enable_point_in_time_recovery` | Enable PITR for Firestore | `false` | `bool` |
| `cors_allowed_origins` | CORS allowed origins | `["*"]` | `list(string)` |

### Full Configuration Example

```hcl
# terraform.tfvars
project_id = "my-url-shortener-project"
region     = "us-central1"

# Function Configuration
function_name        = "my-url-shortener"
function_memory     = "512M"
function_timeout    = 30
function_max_instances = 50
function_min_instances = 1

# Firestore Configuration
firestore_location = "us-central1"
enable_point_in_time_recovery = true
enable_delete_protection = true

# Security Configuration
allow_unauthenticated_access = true
cors_allowed_origins = ["https://myapp.com", "https://admin.myapp.com"]
cors_allowed_methods = ["GET", "POST", "OPTIONS"]

# Storage Configuration
source_bucket_name = "my-function-source"
source_bucket_location = "US"

# Resource Labels
resource_labels = {
  application = "url-shortener"
  environment = "production"
  team        = "platform"
  cost-center = "engineering"
  managed-by  = "terraform"
}
```

## API Endpoints

The deployed function provides the following endpoints:

### Shorten URL
```http
POST /shorten
Content-Type: application/json

{
  "url": "https://example.com/very/long/url"
}
```

**Response:**
```json
{
  "success": true,
  "shortUrl": "https://us-central1-project.cloudfunctions.net/url-shortener/AbC123",
  "shortId": "AbC123",
  "originalUrl": "https://example.com/very/long/url",
  "createdAt": "2024-01-15T10:30:00.000Z"
}
```

### Redirect to Original URL
```http
GET /{shortId}
```
Returns a 301 redirect to the original URL.

### Get Statistics
```http
GET /stats?shortId={shortId}
```

**Response:**
```json
{
  "shortId": "AbC123",
  "originalUrl": "https://example.com/very/long/url",
  "clickCount": 42,
  "createdAt": "2024-01-15T10:30:00.000Z",
  "lastAccessed": "2024-01-15T15:45:30.000Z"
}
```

### Health Check
```http
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "service": "URL Shortener",
  "timestamp": "2024-01-15T16:00:00.000Z",
  "version": "1.0.0"
}
```

## Outputs

After deployment, Terraform provides these outputs:

- `function_url`: HTTPS URL of the deployed function
- `function_name`: Name of the Cloud Function
- `firestore_database_name`: Firestore database identifier
- `api_endpoints`: Complete endpoint information
- `usage_examples`: curl command examples

## Security

### IAM and Access Control

- **Service Account**: Dedicated service account with minimal permissions
- **Firestore Rules**: Public read access for redirects, write access restricted to the function
- **Function Access**: Configurable public access (can be disabled for private use)

### Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read access to url-mappings for redirects
    match /url-mappings/{shortId} {
      allow read: if true;
      allow write: if false; // Only Cloud Function can write
    }
    
    // Deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

### Best Practices

1. **Enable Authentication**: Set `allow_unauthenticated_access = false` for internal use
2. **Configure CORS**: Limit `cors_allowed_origins` to your domains
3. **Enable Monitoring**: Use Cloud Monitoring for alerts and dashboards
4. **Set Resource Limits**: Configure appropriate instance limits for your workload
5. **Use Labels**: Apply consistent resource labels for cost tracking and organization

## Cost Optimization

### Pricing Components

- **Cloud Functions**: Pay-per-invocation and compute time
- **Firestore**: Pay-per-operation and storage
- **Cloud Storage**: Minimal cost for source code storage

### Free Tier Limits

- **Cloud Functions**: 2 million invocations per month
- **Firestore**: 50,000 reads and 20,000 writes per day
- **Cloud Storage**: 5 GB storage per month

### Cost Optimization Tips

1. **Set `function_min_instances = 0`** for maximum cost savings (accepts cold starts)
2. **Use appropriate memory allocation** based on actual usage
3. **Monitor and adjust timeout settings** to avoid unnecessary charges
4. **Leverage Firestore free tier** for small-scale applications
5. **Consider regional deployment** for lower latency and costs

## Monitoring and Observability

### Cloud Logging

Function logs are automatically sent to Cloud Logging. Filter by:
```
resource.type="cloud_function"
resource.labels.function_name="your-function-name"
```

### Cloud Monitoring

Key metrics to monitor:
- Function invocation count and errors
- Function execution time and memory usage
- Firestore read/write operations
- HTTP response codes and latency

### Recommended Alerts

1. **High Error Rate**: Alert when error rate exceeds 5%
2. **High Latency**: Alert when P95 latency exceeds 5 seconds
3. **Quota Limits**: Alert when approaching API quotas
4. **Cost Anomalies**: Alert on unexpected cost increases

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure required APIs are enabled in GCP Console
2. **Insufficient Permissions**: Verify service account has required roles
3. **Firestore Database**: Ensure Firestore is in Native mode, not Datastore mode
4. **CORS Issues**: Configure appropriate CORS settings for web applications

### Debug Commands

```bash
# Check function logs
gcloud functions logs read your-function-name --limit 50

# Test function locally (requires Functions Framework)
functions-framework --target=urlShortener --source=function-source/

# Check Firestore data
gcloud firestore collections list
```

## Customization

### Extending the Function

The function source code is in `function-source/index.js`. You can:

1. Add authentication/authorization
2. Implement custom short ID generation
3. Add analytics and tracking
4. Integrate with external APIs
5. Add rate limiting

### Custom Domains

To use a custom domain:

1. Set up Cloud Load Balancer
2. Configure SSL certificate
3. Point your domain to the load balancer
4. Update CORS configuration

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all data in Firestore and remove all infrastructure.

## Support

For issues with this Terraform module:

1. Check the [troubleshooting section](#troubleshooting)
2. Review Terraform and Google Cloud documentation
3. Check Cloud Logging for function errors
4. Verify IAM permissions and API enablement

## License

This Terraform module is provided as-is for educational and reference purposes.