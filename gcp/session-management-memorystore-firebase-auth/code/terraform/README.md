# Session Management Infrastructure - Terraform

This Terraform configuration deploys a comprehensive session management system using Google Cloud Memorystore for Redis and Firebase Authentication. The infrastructure provides high-performance, scalable session storage with automated cleanup and monitoring capabilities.

## Architecture Overview

The solution includes:

- **Cloud Memorystore Redis Instance**: High-performance session storage with microsecond latency
- **Firebase Authentication Integration**: Secure user authentication and token validation
- **Cloud Functions**: Serverless session management and automated cleanup
- **Secret Manager**: Secure storage of Redis connection credentials
- **Cloud Scheduler**: Automated session cleanup every 6 hours
- **Monitoring & Alerting**: Redis memory usage monitoring and session analytics

## Prerequisites

1. Google Cloud Project with billing enabled
2. Terraform >= 1.0 installed
3. Google Cloud CLI installed and authenticated
4. Firebase project set up with Authentication enabled
5. Required APIs enabled (automatically enabled by this configuration)

## Required Google Cloud APIs

The following APIs will be automatically enabled:
- Cloud Memorystore for Redis API
- Cloud Functions API
- Secret Manager API
- Cloud Scheduler API
- Cloud Logging API
- Cloud Monitoring API
- Firebase API
- Cloud Build API
- Cloud Storage API
- Cloud Run API

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd gcp/session-management-memorystore-firebase-auth/code/terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Create Variables File**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

4. **Configure Variables**:
   Edit `terraform.tfvars` with your project-specific values:
   ```hcl
   project_id = "your-gcp-project-id"
   region     = "us-central1"
   zone       = "us-central1-a"
   ```

5. **Plan Deployment**:
   ```bash
   terraform plan
   ```

6. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud Project ID | `"my-project-123"` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `"us-central1"` | Google Cloud region |
| `zone` | `"us-central1-a"` | Google Cloud zone |
| `redis_instance_name` | `"session-store"` | Redis instance name |
| `redis_memory_size_gb` | `1` | Redis memory size (1-300 GB) |
| `redis_tier` | `"BASIC"` | Redis tier (BASIC/STANDARD_HA) |
| `function_memory` | `"512M"` | Cloud Function memory |
| `function_timeout` | `60` | Function timeout in seconds |
| `cleanup_schedule` | `"0 */6 * * *"` | Cleanup cron schedule |
| `session_ttl_hours` | `24` | Session TTL for cleanup |
| `deletion_protection` | `false` | Enable deletion protection |

## Example terraform.tfvars

```hcl
# Project Configuration
project_id = "my-gcp-project"
region     = "us-central1"
zone       = "us-central1-a"

# Redis Configuration
redis_memory_size_gb = 2
redis_tier          = "STANDARD_HA"

# Function Configuration
function_memory  = "1G"
function_timeout = 120

# Session Configuration
session_ttl_hours = 48
cleanup_schedule  = "0 */4 * * *"  # Every 4 hours

# Security
deletion_protection = true

# Labels
labels = {
  environment = "production"
  team        = "platform"
  cost-center = "engineering"
}
```

## Outputs

After deployment, important values are available as outputs:

```bash
# Get Redis connection details
terraform output redis_host
terraform output redis_port

# Get function URLs
terraform output session_manager_function_url
terraform output session_cleanup_function_url

# Get complete configuration
terraform output session_configuration
```

## Usage Examples

### Session Management API

The deployed session manager function provides these endpoints:

#### Create Session
```bash
curl -X POST "$(terraform output -raw session_manager_function_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "create",
    "token": "FIREBASE_ID_TOKEN",
    "sessionData": {
      "device": "web",
      "location": "office"
    }
  }'
```

#### Validate Session
```bash
curl -X POST "$(terraform output -raw session_manager_function_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "validate",
    "token": "FIREBASE_ID_TOKEN"
  }'
```

#### Destroy Session
```bash
curl -X POST "$(terraform output -raw session_manager_function_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "destroy",
    "sessionId": "session:USER_ID"
  }'
```

### Manual Cleanup Trigger
```bash
curl -X POST "$(terraform output -raw session_cleanup_function_url)" \
  -H "Content-Type: application/json" \
  -d '{"trigger": "manual"}'
```

## Monitoring and Alerting

### Built-in Monitoring

1. **Redis Memory Alert**: Triggers when memory usage exceeds 80%
2. **Session Analytics**: Logs are sent to BigQuery for analysis
3. **Function Logs**: Detailed logging for all session operations

### Viewing Logs

```bash
# Session manager logs
gcloud functions logs read session-manager-SUFFIX --region=us-central1

# Cleanup function logs
gcloud functions logs read session-cleanup-SUFFIX --region=us-central1
```

### Monitoring Dashboard

Access Cloud Monitoring to view:
- Redis instance metrics
- Function execution metrics
- Session creation/validation rates
- Error rates and latency

## Security Features

1. **Authentication**: Firebase token validation for all operations
2. **Encryption**: Redis AUTH and transit encryption enabled
3. **Secret Management**: Connection details stored in Secret Manager
4. **IAM**: Least privilege service account permissions
5. **Network Security**: Internal-only access for cleanup function

## Cost Optimization

### Cost Factors

- **Redis Instance**: Primary cost based on memory size and tier
- **Cloud Functions**: Pay-per-invocation with automatic scaling
- **Secret Manager**: Minimal cost for secret operations
- **Cloud Scheduler**: Fixed monthly cost for job execution

### Optimization Tips

1. **Right-size Redis**: Start with 1GB and monitor usage
2. **Session TTL**: Shorter TTL reduces memory usage
3. **Cleanup Frequency**: More frequent cleanup optimizes memory
4. **Function Memory**: Use minimum required memory allocation

## Troubleshooting

### Common Issues

1. **Redis Connection Timeout**:
   ```bash
   # Check Redis instance status
   gcloud redis instances describe $(terraform output -raw redis_instance_name) --region=$(terraform output -raw region)
   ```

2. **Function Permission Errors**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy $(terraform output -raw project_id)
   ```

3. **Secret Access Issues**:
   ```bash
   # Test secret access
   gcloud secrets versions access latest --secret=$(terraform output -raw secret_manager_secret_name)
   ```

### Debug Mode

Enable debug logging by adding environment variables:

```hcl
# In terraform.tfvars
function_debug = true
```

## Backup and Recovery

### Redis Backup (STANDARD_HA only)

Automatic point-in-time recovery is available for STANDARD_HA tier:

```bash
# Create manual backup
gcloud redis instances export gs://backup-bucket/redis-backup.rdb \
  --source=$(terraform output -raw redis_instance_name) \
  --region=$(terraform output -raw region)
```

### Configuration Backup

Always backup your Terraform state:

```bash
# Export Terraform state
terraform state pull > terraform-state-backup.json
```

## Scaling Considerations

### Vertical Scaling
- Increase Redis memory size in `terraform.tfvars`
- Update function memory allocation if needed

### Horizontal Scaling
- Upgrade to STANDARD_HA tier for high availability
- Consider multiple regions for global deployment

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm resource removal
gcloud redis instances list
gcloud functions list
```

**Warning**: This will permanently delete all session data.

## Support

For issues with this infrastructure:

1. Check the [GCP Recipe Documentation](../../README.md)
2. Review Cloud Function logs for errors
3. Monitor Redis instance health in Cloud Console
4. Verify Secret Manager access permissions

## Version History

- **v1.0**: Initial Terraform configuration
  - Basic Redis instance with Cloud Functions
  - Firebase Auth integration
  - Automated cleanup with Cloud Scheduler
  - Monitoring and alerting setup