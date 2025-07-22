# Network Performance Optimization with Cloud WAN and Network Intelligence Center

This Terraform configuration deploys a comprehensive network performance optimization solution on Google Cloud Platform, combining Cloud WAN, Network Intelligence Center, and automated monitoring capabilities for enterprise network performance management.

## Solution Overview

This infrastructure as code (IaC) deployment creates an intelligent network operations system that leverages:

- **Google Cloud WAN** via Network Connectivity Center for global network management
- **Network Intelligence Center** for AI-powered network observability and analysis
- **Cloud Functions** for automated optimization and remediation
- **Cloud Monitoring** for real-time performance tracking and alerting
- **Pub/Sub** for event-driven automation workflows
- **Cloud Scheduler** for periodic analysis and reporting

## Architecture

The solution deploys the following components:

### Core Infrastructure
- VPC network with optimized subnets and VPC Flow Logs
- Network Connectivity Hub for global network management
- Compute instances for connectivity testing
- Service accounts with least-privilege IAM permissions

### Network Intelligence Center Integration
- Connectivity Tests for proactive network validation
- VPC Flow Logs configuration for traffic analysis
- Performance monitoring dashboards
- Automated network health assessment

### Automation and Monitoring
- Cloud Functions for intelligent optimization processing
- Pub/Sub topics for event-driven workflows
- Cloud Monitoring alerts and dashboards
- Scheduled analysis and reporting via Cloud Scheduler

## Prerequisites

Before deploying this solution, ensure you have:

1. **Google Cloud Project**: With billing enabled and appropriate quotas
2. **Terraform**: Version 1.0 or higher installed locally
3. **Google Cloud CLI**: Installed and authenticated (`gcloud auth login`)
4. **Required APIs**: Will be automatically enabled during deployment
5. **IAM Permissions**: Project Editor or custom roles with necessary permissions
6. **Network Planning**: Understand your network topology and requirements

### Required Google Cloud APIs

The following APIs will be automatically enabled:
- Network Connectivity API
- Network Management API  
- Cloud Monitoring API
- Cloud Functions API
- Pub/Sub API
- Cloud Scheduler API
- Compute Engine API
- Cloud Storage API
- Cloud Logging API

## Quick Start

### 1. Clone and Prepare

```bash
# Navigate to the terraform directory
cd gcp/network-performance-optimization-wan-network-intelligence-center/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars
```

### 2. Configure Variables

Edit `terraform.tfvars` with your specific values:

```hcl
project_id = "your-gcp-project-id"
region = "us-central1"
secondary_region = "us-west1"
notification_email = "your-email@company.com"
environment = "production"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

```bash
# Check connectivity tests
gcloud network-management connectivity-tests list --project=your-project-id

# View monitoring dashboard
echo "Dashboard URL: $(terraform output monitoring_dashboard_url)"

# Test function trigger
gcloud pubsub topics publish $(terraform output network_events_topic_name) \
    --message='{"test":"true"}' --project=your-project-id
```

## Configuration

### Essential Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | No |
| `notification_email` | Email for alerts | - | Yes |
| `environment` | Environment designation | `production` | No |

### Network Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `primary_subnet_cidr` | Primary subnet CIDR | `10.0.1.0/24` |
| `secondary_subnet_cidr` | Secondary subnet CIDR | `10.0.2.0/24` |
| `vpc_flow_logs_sampling` | Flow logs sampling rate | `0.1` |
| `network_mtu` | VPC network MTU | `1500` |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `latency_threshold_ms` | Latency alert threshold | `100` |
| `throughput_threshold_bps` | Throughput threshold | `1000000` |
| `enable_detailed_monitoring` | Enable detailed metrics | `true` |

### Function Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `function_memory` | Function memory allocation | `512Mi` |
| `function_timeout_seconds` | Function timeout | `300` |
| `function_max_instances` | Max concurrent instances | `10` |

For complete configuration options, see `variables.tf`.

## Outputs

After successful deployment, Terraform provides essential information:

### Infrastructure Outputs
- VPC network and subnet details
- Network Connectivity Hub information
- Compute instance IP addresses and zones

### Service Endpoints
- Cloud Function URLs and service accounts
- Pub/Sub topic and subscription names
- Storage bucket information

### Monitoring and Operations
- Monitoring dashboard URL
- Network Intelligence Center URLs
- Alert policy and notification channel IDs

### Validation Commands
- Connectivity test verification commands
- Function testing commands
- Log analysis commands

Access outputs with:
```bash
terraform output
terraform output -json > outputs.json
```

## Usage

### Manual Testing

Test the network optimization function:
```bash
# Trigger optimization analysis
gcloud pubsub topics publish TOPIC_NAME \
    --message='{"action":"analyze","priority":"high"}'

# View function logs
gcloud functions logs read FUNCTION_NAME --region=REGION --limit=10
```

### Monitoring Network Performance

1. **Access Network Intelligence Center**: Use the provided URL to view connectivity tests and network analysis
2. **View Monitoring Dashboard**: Check the custom dashboard for performance metrics
3. **Review VPC Flow Logs**: Analyze traffic patterns in Cloud Logging
4. **Check Alert Policies**: Monitor alert status in Cloud Monitoring

### Automated Operations

The solution automatically:
- Runs periodic network analysis every 6 hours (configurable)
- Generates daily network health reports
- Triggers optimization actions based on performance thresholds
- Sends email notifications for performance issues

## Customization

### Adding Custom Optimization Logic

Modify `function_code/main.py` to implement custom optimization strategies:

```python
def custom_optimization_strategy(metrics: NetworkMetrics) -> List[OptimizationAction]:
    """Implement your custom optimization logic here"""
    actions = []
    
    # Add your custom logic
    if metrics.latency_ms > custom_threshold:
        actions.append(OptimizationAction(...))
    
    return actions
```

### Custom Monitoring Metrics

Add custom metrics to the monitoring dashboard by modifying the dashboard JSON in `main.tf`.

### Integration with External Systems

Use the Pub/Sub topics to integrate with external monitoring or automation systems:

```bash
# Subscribe to optimization events
gcloud pubsub subscriptions create external-integration \
    --topic=network-optimization-events
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Verify authentication
   gcloud auth list
   
   # Check project permissions
   gcloud projects get-iam-policy PROJECT_ID
   ```

2. **API Not Enabled**
   ```bash
   # Enable required APIs manually
   gcloud services enable networkmanagement.googleapis.com
   ```

3. **Function Deployment Failures**
   ```bash
   # Check function logs
   gcloud functions logs read FUNCTION_NAME --region=REGION
   
   # Verify source code package
   ls -la *.zip
   ```

4. **Connectivity Test Failures**
   ```bash
   # Check test status
   gcloud network-management connectivity-tests describe TEST_NAME
   
   # Review test results
   gcloud network-management connectivity-tests list
   ```

### Debugging Commands

```bash
# View all deployed resources
terraform state list

# Check resource status
terraform show

# Validate configuration
terraform validate

# Check for drift
terraform plan -detailed-exitcode
```

### Log Analysis

```bash
# Function execution logs
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name="FUNCTION_NAME"' --limit=20

# VPC Flow Logs
gcloud logging read 'resource.type="gce_subnetwork"' --limit=10

# Monitoring alerts
gcloud logging read 'resource.type="monitoring_policy"' --limit=10
```

## Cost Optimization

### Estimated Monthly Costs

| Component | Estimated Cost (USD) |
|-----------|---------------------|
| Compute Instances | $50-100 |
| VPC Flow Logs | $20-100 |
| Cloud Functions | $5-20 |
| Cloud Monitoring | $10-30 |
| Pub/Sub | $5-15 |
| Storage | $2-10 |
| **Total** | **$92-275** |

### Cost Reduction Strategies

1. **Reduce VPC Flow Logs Sampling**: Set `vpc_flow_logs_sampling = 0.05` for development
2. **Use Smaller Instances**: Set `test_instance_machine_type = "e2-micro"` for testing
3. **Disable Detailed Monitoring**: Set `enable_detailed_monitoring = false` for non-production
4. **Adjust Function Memory**: Use `function_memory = "256Mi"` if sufficient
5. **Optimize Scheduling**: Reduce analysis frequency with `analysis_schedule = "0 */12 * * *"`

## Security

### Security Features

- **IAM**: Least-privilege service accounts
- **Network Security**: Private IP addresses, no external access by default
- **Encryption**: Data encrypted in transit and at rest
- **Access Control**: OS Login enabled for secure instance access
- **Monitoring**: Comprehensive audit logging

### Security Best Practices

1. **Regular Updates**: Keep Terraform providers and dependencies updated
2. **Access Review**: Regularly review IAM permissions and access patterns
3. **Network Segmentation**: Use firewall rules to restrict network access
4. **Secret Management**: Use Google Secret Manager for sensitive configuration
5. **Monitoring**: Enable security monitoring and alerting

## Maintenance

### Regular Tasks

1. **Weekly**: Review monitoring dashboards and alerts
2. **Monthly**: Update Terraform providers and review costs
3. **Quarterly**: Review and update optimization thresholds
4. **Annually**: Conduct comprehensive security and performance review

### Updating the Solution

```bash
# Update Terraform providers
terraform init -upgrade

# Review changes
terraform plan

# Apply updates
terraform apply
```

### Backup and Recovery

```bash
# Export Terraform state
terraform state pull > terraform.tfstate.backup

# Export resource configurations
terraform show -json > resources.json

# Backup custom configurations
cp terraform.tfvars terraform.tfvars.backup
```

## Support and Documentation

### Additional Resources

- [Google Cloud Network Intelligence Center Documentation](https://cloud.google.com/network-intelligence-center/docs)
- [Cloud WAN Documentation](https://cloud.google.com/solutions/cross-cloud-network)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Network Performance Best Practices](https://cloud.google.com/architecture/framework/network)

### Getting Help

1. **Documentation**: Check the official Google Cloud documentation
2. **Community**: Use Stack Overflow with `google-cloud-platform` tag
3. **Support**: Contact Google Cloud Support for production issues
4. **Issues**: Report bugs or feature requests in your organization's issue tracker

## Contributing

To contribute improvements to this solution:

1. Test changes in a development environment
2. Update documentation for any new features
3. Follow security best practices
4. Include appropriate test coverage
5. Update the changelog for significant changes

## License

This Terraform configuration is provided as-is for educational and operational use. Ensure compliance with your organization's policies and Google Cloud terms of service.