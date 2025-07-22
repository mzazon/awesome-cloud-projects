# Infrastructure as Code for Session Management with Cloud Memorystore and Firebase Auth

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Session Management with Cloud Memorystore and Firebase Auth".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a high-performance session management system combining:
- Cloud Memorystore for Redis (microsecond-latency session storage)
- Firebase Authentication (user identity management)
- Cloud Functions (serverless session operations)
- Secret Manager (secure configuration storage)
- Cloud Scheduler (automated session cleanup)

## Prerequisites

- Google Cloud account with billing enabled
- Google Cloud CLI (`gcloud`) installed and configured
- Terraform 1.0+ installed (for Terraform implementation)
- Appropriate Google Cloud permissions:
  - Cloud Memorystore Admin
  - Cloud Functions Admin
  - Secret Manager Admin
  - Firebase Admin
  - Cloud Scheduler Admin
  - IAM Admin
- Firebase project initialized for the target Google Cloud project

## Environment Setup

```bash
# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"

# Configure gcloud defaults
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required APIs
gcloud services enable redis.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable firebase.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
```

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses Terraform-compatible syntax.

```bash
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/session-management \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --local-source="." \
    --inputs-file=terraform.tfvars

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/session-management
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Configuration

### Infrastructure Manager Variables

Edit `infrastructure-manager/terraform.tfvars` to customize:

```hcl
project_id     = "your-project-id"
region         = "us-central1"
zone           = "us-central1-a"
redis_memory_size_gb = 1
function_memory_mb = 512
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Redis configuration
redis_instance_name = "session-store"
redis_memory_size_gb = 1
redis_tier = "BASIC"

# Function configuration
session_function_memory = 512
cleanup_function_memory = 256

# Cleanup schedule (cron format)
cleanup_schedule = "0 */6 * * *"

# Labels for resource organization
labels = {
  purpose     = "session-management"
  environment = "production"
}
```

## Validation

After deployment, validate the infrastructure:

```bash
# Check Redis instance status
gcloud redis instances describe session-store --region=${REGION}

# Verify Cloud Functions
gcloud functions list --regions=${REGION}

# Test Secret Manager access
gcloud secrets versions access latest --secret=redis-connection

# Check Cloud Scheduler jobs
gcloud scheduler jobs list --location=${REGION}

# View monitoring dashboards
echo "Check Cloud Console for monitoring dashboards and logs"
```

## Monitoring and Logging

The deployed infrastructure includes:

1. **Cloud Monitoring**:
   - Redis instance metrics (memory usage, connections, operations)
   - Cloud Functions metrics (invocations, duration, errors)
   - Custom session management metrics

2. **Cloud Logging**:
   - Session operation logs
   - Cleanup operation logs
   - Error and audit logs

3. **Alerting Policies**:
   - Redis memory usage alerts
   - Function error rate alerts
   - Session cleanup failure alerts

Access logs:
```bash
# View session manager logs
gcloud functions logs read session-manager --region=${REGION}

# View cleanup function logs
gcloud functions logs read session-cleanup --region=${REGION}

# View Redis instance logs
gcloud logging read "resource.type=redis_instance"
```

## Security Features

The implementation includes:

1. **IAM Security**:
   - Principle of least privilege for service accounts
   - Function-specific IAM roles
   - Secret Manager access controls

2. **Network Security**:
   - Private Redis instance (no public IP)
   - VPC-native networking for functions
   - Authorized networks configuration

3. **Data Security**:
   - Secrets stored in Secret Manager
   - Redis AUTH enabled
   - Encrypted connections (TLS)

4. **Audit Logging**:
   - All operations logged to Cloud Logging
   - Access audit trails
   - Configuration change tracking

## Cost Optimization

Estimated monthly costs (US regions):
- Redis Basic Tier (1GB): ~$25-30
- Cloud Functions: $0.00001 per 100ms (minimal for session operations)
- Secret Manager: $0.06 per 10,000 operations
- Cloud Scheduler: $0.10 per job per month

Cost optimization tips:
- Use Redis Basic tier for development environments
- Enable Cloud Functions concurrency for better performance
- Implement session analytics to optimize cleanup schedules
- Monitor unused sessions to adjust timeout policies

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/

# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/session-management
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are removed
./scripts/verify-cleanup.sh
```

## Troubleshooting

### Common Issues

1. **Redis Connection Failures**:
   ```bash
   # Check Redis instance status
   gcloud redis instances describe session-store --region=${REGION}
   
   # Verify network connectivity
   gcloud compute networks describe default
   ```

2. **Function Deployment Errors**:
   ```bash
   # Check function logs
   gcloud functions logs read session-manager --region=${REGION}
   
   # Verify IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Secret Manager Access Issues**:
   ```bash
   # Test secret access
   gcloud secrets versions access latest --secret=redis-connection
   
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:*appspot*"
   ```

### Debug Commands

```bash
# Enable debug logging for all components
export TF_LOG=DEBUG  # For Terraform
export GOOGLE_CLOUD_DEBUG=true  # For gcloud

# Check API enablement
gcloud services list --enabled

# Verify quotas
gcloud compute project-info describe --format="table(quotas[].metric,quotas[].limit,quotas[].usage)"
```

## Customization

### Adding Custom Session Fields

To extend session data structure:

1. Modify the Cloud Function code in `session-function/index.js`
2. Update Redis schema validation
3. Redeploy functions using your preferred IaC method

### Scaling Configuration

For higher traffic loads:

1. **Redis Scaling**:
   - Upgrade to Standard tier for high availability
   - Increase memory size
   - Enable read replicas

2. **Function Scaling**:
   - Increase memory allocation
   - Configure concurrency settings
   - Enable max instances limit

3. **Monitoring Enhancement**:
   - Add custom metrics
   - Create SLI/SLO dashboards
   - Implement alerting rules

### Multi-Region Deployment

For global session management:

1. Deploy Redis instances in multiple regions
2. Configure session routing based on user location
3. Implement cross-region session synchronization
4. Set up global load balancing

## Integration Examples

### Web Application Integration

```javascript
// Example session creation
const response = await fetch(FUNCTION_URL, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    action: 'create',
    token: firebaseIdToken,
    sessionData: { device: 'web', location: userLocation }
  })
});
```

### Mobile Application Integration

```swift
// iOS example
let sessionData = [
  "action": "validate",
  "token": idToken,
  "sessionData": ["device": "ios", "version": appVersion]
]
```

## Performance Benchmarks

Expected performance characteristics:
- Session creation: < 50ms
- Session validation: < 10ms
- Cleanup operations: < 5 minutes for 100k sessions
- Redis latency: < 1ms for 95th percentile

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation:
   - [Cloud Memorystore](https://cloud.google.com/memorystore/docs)
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Firebase Authentication](https://firebase.google.com/docs/auth)
4. Submit issues to the recipe repository

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any configuration changes
4. Validate security implications of modifications