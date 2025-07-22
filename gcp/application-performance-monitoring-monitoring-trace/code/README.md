# Infrastructure as Code for Application Performance Monitoring with Cloud Monitoring and Cloud Trace

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Application Performance Monitoring with Cloud Monitoring and Cloud Trace".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Compute Admin
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Monitoring Admin
  - Service Usage Admin
- Terraform v1.0+ (for Terraform deployment)
- Basic understanding of application performance monitoring concepts

## Quick Start

### Using Infrastructure Manager

```bash
# Create deployment using Infrastructure Manager
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply \
    projects/PROJECT_ID/locations/REGION/deployments/performance-monitoring \
    --service-account=SERVICE_ACCOUNT \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe \
    projects/PROJECT_ID/locations/REGION/deployments/performance-monitoring
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud compute instances list
gcloud functions list
gcloud pubsub topics list
```

## Architecture Overview

This infrastructure deploys a comprehensive application performance monitoring solution including:

- **Compute Engine Instance**: Sample web application with monitoring instrumentation
- **Cloud Functions**: Automated performance optimization function
- **Pub/Sub Topic & Subscription**: Event-driven alert distribution
- **Cloud Monitoring**: Custom metrics, alert policies, and dashboards
- **Cloud Trace**: Distributed tracing for performance analysis
- **IAM Roles & Policies**: Secure access configuration

## Configuration

### Environment Variables

Before deployment, set the following environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
```

### Customizable Parameters

The following parameters can be customized in the deployment:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `project_id` | Google Cloud Project ID | Required |
| `region` | Deployment region | `us-central1` |
| `zone` | Compute Engine zone | `us-central1-a` |
| `machine_type` | Instance machine type | `e2-medium` |
| `alert_threshold` | Response time alert threshold (seconds) | `1.5` |
| `function_memory` | Cloud Function memory allocation | `256MB` |
| `function_timeout` | Cloud Function timeout | `60s` |

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
machine_type = "e2-medium"
alert_threshold = 1.5
```

### Infrastructure Manager Configuration

Edit `infrastructure-manager/main.yaml` to customize deployment parameters according to your requirements.

## Post-Deployment

### Validation Steps

1. **Verify Application Deployment**:
   ```bash
   # Get instance external IP
   INSTANCE_IP=$(gcloud compute instances describe web-app-* \
       --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
   
   # Test application endpoint
   curl "http://${INSTANCE_IP}:5000/health"
   ```

2. **Check Monitoring Configuration**:
   ```bash
   # List custom metrics
   gcloud monitoring metrics list \
       --filter="metric.type:custom.googleapis.com/api/response_time"
   
   # Verify alert policies
   gcloud alpha monitoring policies list
   ```

3. **Test Cloud Function**:
   ```bash
   # Check function deployment
   gcloud functions describe performance-optimizer-*
   
   # View function logs
   gcloud functions logs read performance-optimizer-*
   ```

### Access Points

- **Application URL**: `http://[INSTANCE_IP]:5000`
- **Health Endpoint**: `http://[INSTANCE_IP]:5000/health`
- **API Endpoint**: `http://[INSTANCE_IP]:5000/api/data`
- **Monitoring Dashboard**: [Google Cloud Console - Monitoring](https://console.cloud.google.com/monitoring)
- **Cloud Trace**: [Google Cloud Console - Trace](https://console.cloud.google.com/traces)

## Testing the Solution

### Generate Test Traffic

```bash
# Create traffic generation script
cat > generate_traffic.sh << 'EOF'
#!/bin/bash
INSTANCE_IP=$1
APP_URL="http://${INSTANCE_IP}:5000"

echo "Generating normal traffic..."
for i in {1..20}; do
    curl -s "${APP_URL}/api/data" > /dev/null
    sleep 2
done

echo "Generating high-latency traffic to trigger alerts..."
for i in {1..10}; do
    curl -s "${APP_URL}/api/data" &
    curl -s "${APP_URL}/api/data" &
    curl -s "${APP_URL}/api/data" &
    wait
    sleep 1
done
EOF

chmod +x generate_traffic.sh

# Run traffic generation
./generate_traffic.sh [INSTANCE_IP]
```

### Monitor Results

```bash
# Check alert policy triggers
gcloud alpha monitoring policies list \
    --filter="displayName:'High API Response Time Alert'"

# View function execution logs
gcloud functions logs read performance-optimizer-* --limit=10

# Check Pub/Sub message processing
gcloud pubsub subscriptions pull performance-alerts-*-subscription \
    --auto-ack --limit=5
```

## Troubleshooting

### Common Issues

1. **Application Not Accessible**:
   - Verify firewall rules are created
   - Check instance startup script execution
   - Confirm application is running on port 5000

2. **Monitoring Data Not Appearing**:
   - Verify Cloud Monitoring API is enabled
   - Check application is sending custom metrics
   - Confirm service account permissions

3. **Cloud Function Not Triggering**:
   - Check Pub/Sub topic and subscription configuration
   - Verify alert policy notification channel setup
   - Review function logs for errors

### Debug Commands

```bash
# Check instance startup script logs
gcloud compute instances get-serial-port-output web-app-*

# Verify API enablement
gcloud services list --enabled

# Check IAM permissions
gcloud projects get-iam-policy PROJECT_ID

# View detailed function information
gcloud functions describe performance-optimizer-* --format=yaml
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/PROJECT_ID/locations/REGION/deployments/performance-monitoring

# Verify deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource cleanup
gcloud compute instances list
gcloud functions list
gcloud pubsub topics list
```

### Manual Cleanup (if needed)

```bash
# Delete remaining resources manually
gcloud compute instances delete web-app-* --zone=us-central1-a --quiet
gcloud functions delete performance-optimizer-* --quiet
gcloud pubsub subscriptions delete performance-alerts-*-subscription --quiet
gcloud pubsub topics delete performance-alerts-* --quiet
gcloud compute firewall-rules delete allow-web-app --quiet

# Delete monitoring resources
gcloud alpha monitoring policies delete [POLICY_NAME] --quiet
gcloud alpha monitoring channels delete [CHANNEL_NAME] --quiet
gcloud monitoring dashboards delete [DASHBOARD_ID] --quiet
```

## Cost Considerations

### Estimated Monthly Costs

- **Compute Engine e2-medium**: ~$25/month (if running continuously)
- **Cloud Functions**: ~$0.10-1.00/month (based on executions)
- **Pub/Sub**: ~$0.10-0.50/month (based on message volume)
- **Cloud Monitoring**: ~$1-5/month (based on metrics ingestion)
- **Cloud Trace**: ~$0.50-2.00/month (based on trace volume)

**Total Estimated Cost**: $27-34/month

### Cost Optimization Tips

- Stop Compute Engine instances when not in use
- Use sustained use discounts for long-running instances
- Monitor and adjust alert thresholds to reduce false positives
- Implement log retention policies to manage storage costs

## Security Considerations

- Application runs with minimal required permissions
- Cloud Function uses service account with least privilege access
- Firewall rules restrict access to necessary ports only
- All resources are tagged for proper resource management
- Monitoring data is encrypted in transit and at rest

## Support and Documentation

- [Google Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Cloud Trace Documentation](https://cloud.google.com/trace/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Google Cloud best practices
3. Update documentation for any parameter changes
4. Ensure cleanup procedures work correctly

## License

This infrastructure code is provided as-is for educational and demonstration purposes.