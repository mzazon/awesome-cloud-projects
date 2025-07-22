# Infrastructure as Code for Disaster Recovery Orchestration with Service Extensions and Backup and DR Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Disaster Recovery Orchestration with Service Extensions and Backup and DR Service".

## Overview

This solution creates an intelligent disaster recovery system that leverages Google Cloud Load Balancing service extensions to detect infrastructure failures in real-time and automatically orchestrate backup restoration workflows. The system combines edge-level failure detection, serverless orchestration, and automated recovery operations to minimize downtime and reduce manual intervention during critical failure scenarios.

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

- **Primary Infrastructure**: Compute Engine instances with auto-scaling groups
- **Disaster Recovery Infrastructure**: Standby resources in alternate region
- **Load Balancing**: Global HTTP(S) load balancer with service extensions
- **Orchestration**: Cloud Functions for automated DR workflows
- **Backup Services**: Backup and DR Service with immutable vault storage
- **Monitoring**: Cloud Monitoring with custom metrics and alerting

## Prerequisites

### General Requirements
- Google Cloud Project with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Project Owner or Editor permissions for the following APIs:
  - Compute Engine API
  - Cloud Functions API
  - Backup and DR Service API
  - Cloud Monitoring API
  - Cloud Logging API
  - Service Extensions API
- Basic understanding of load balancing, serverless functions, and disaster recovery concepts

### Cost Estimate
- **Development/Testing**: $50-100 for 2-hour tutorial
- **Production**: Costs scale with actual usage, backup retention, and DR infrastructure

### API Enablement
```bash
gcloud services enable compute.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable backupdr.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable serviceextensions.googleapis.com
```

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DR_REGION="us-east1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/dr-orchestration \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/infrastructure-manager" \
    --git-source-directory="." \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION},dr_region=${DR_REGION}"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan -var="project_id=${PROJECT_ID}" \
               -var="region=${REGION}" \
               -var="dr_region=${DR_REGION}"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" \
                -var="region=${REGION}" \
                -var="dr_region=${DR_REGION}"
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DR_REGION="us-east1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Deployment Steps

### 1. Primary Infrastructure Setup
The deployment creates:
- Compute Engine instance templates for primary application
- Managed instance groups with auto-scaling
- Health checks for application monitoring
- Network security configurations

### 2. Disaster Recovery Infrastructure
Establishes standby infrastructure including:
- DR region instance templates and groups
- Cross-region health monitoring
- Cost-optimized standby configuration (zero instances initially)

### 3. Backup and DR Service Configuration
Configures enterprise-grade data protection:
- Immutable backup vault with 30-day retention
- Automated daily backup plans
- Cross-region backup replication
- Recovery workflow automation

### 4. Load Balancer and Service Extensions
Implements intelligent traffic management:
- Global HTTP(S) load balancer
- Service extensions for real-time failure detection
- Backend service configuration with health checks
- Automatic failover routing rules

### 5. Orchestration Functions
Deploys serverless disaster recovery logic:
- Cloud Functions for DR orchestration
- Integration with Backup and DR Service
- Automated scaling of DR infrastructure
- Custom metrics and monitoring integration

### 6. Monitoring and Alerting
Establishes comprehensive observability:
- Custom log-based metrics for DR events
- Alerting policies for failure detection
- Monitoring dashboards for DR status
- Integration with Cloud Operations Suite

## Configuration Options

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary region for infrastructure | `us-central1` | Yes |
| `dr_region` | Disaster recovery region | `us-east1` | Yes |
| `zone` | Primary zone within region | `us-central1-a` | No |
| `dr_zone` | DR zone within DR region | `us-east1-a` | No |
| `machine_type` | Instance machine type | `e2-micro` | No |
| `backup_retention_days` | Backup retention period | `30` | No |
| `failure_threshold` | Failure count before DR trigger | `5` | No |
| `failure_window_seconds` | Time window for failure counting | `300` | No |

### Infrastructure Manager Parameters

Similar variables are available for Infrastructure Manager deployments, defined in the `infrastructure-manager/main.yaml` file.

## Validation and Testing

### 1. Verify Load Balancer Functionality
```bash
# Get load balancer IP
LB_IP=$(gcloud compute forwarding-rules describe dr-orchestration-forwarding-rule \
    --global --format="value(IPAddress)")

# Test primary application
curl -H "Host: example.com" http://${LB_IP}
```

### 2. Test Disaster Recovery Triggering
```bash
# Simulate failure by scaling down primary instances
gcloud compute instance-groups managed resize primary-app-group \
    --size=0 --zone=${ZONE}

# Monitor Cloud Function logs for DR activation
gcloud functions logs read dr-orchestrator --limit=10
```

### 3. Verify DR Infrastructure Activation
```bash
# Check DR instance group scaling
gcloud compute instance-groups managed describe dr-app-group \
    --zone=${DR_ZONE} --format="value(targetSize)"

# Test DR application after activation
curl -H "Host: example.com" http://${LB_IP}
```

### 4. Validate Backup Service Integration
```bash
# Check backup vault status
gcloud backup-dr backup-vaults describe primary-backup-vault \
    --location=${REGION} --format="value(state)"

# Verify backup plan configuration
gcloud backup-dr backup-plans describe primary-backup-plan \
    --location=${REGION}
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **Failure Detection Events**: Service extension trigger frequency
2. **DR Orchestration Success**: Successful automated recovery operations
3. **Recovery Time Objective (RTO)**: Time from failure to service restoration
4. **Backup Health**: Backup completion status and retention compliance
5. **Infrastructure Health**: Primary and DR resource availability

### Custom Dashboards

The deployment creates monitoring dashboards for:
- Real-time DR event tracking
- Infrastructure health across regions
- Backup operation status
- Service extension performance metrics

### Alerting Policies

Automated alerts are configured for:
- Disaster recovery event triggers
- Backup operation failures
- Service extension errors
- Infrastructure health degradation

## Cleanup

### Using Infrastructure Manager
```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/dr-orchestration
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" \
                  -var="region=${REGION}" \
                  -var="dr_region=${DR_REGION}"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification
```bash
# Verify all resources are removed
gcloud compute instances list --filter="name~'dr-orchestration'"
gcloud functions list --filter="name~'dr-orchestrator'"
gcloud backup-dr backup-vaults list --location=${REGION}
```

## Customization

### Extending Failure Detection

The service extension can be enhanced with additional failure detection logic:

```python
# Add custom failure conditions in extension.py
def detect_custom_failures(self, request_data):
    # Implement business-specific failure detection
    # Examples: API response validation, database connectivity, external service health
    pass
```

### Advanced Recovery Workflows

Enhance the Cloud Function orchestration with:

1. **Multi-step Recovery Procedures**: Implement complex recovery workflows
2. **Data Validation**: Add automated data integrity checks
3. **Gradual Failover**: Implement traffic shifting strategies
4. **Cost Optimization**: Dynamic resource scaling based on failure severity

### Integration with External Systems

The solution can be extended to integrate with:
- External monitoring systems (Datadog, New Relic)
- Incident management platforms (PagerDuty, Opsgenie)
- Business continuity tools
- Compliance reporting systems

## Security Considerations

### IAM and Access Control

- Service accounts follow least privilege principle
- Cross-region access controls for DR operations
- Backup vault encryption with customer-managed keys
- Function-level authentication and authorization

### Network Security

- VPC firewall rules restrict access to necessary ports
- Private Google Access for internal communications
- Load balancer SSL/TLS termination
- Service extension security policies

### Data Protection

- Backup vault immutable storage protection
- Encryption at rest and in transit
- Cross-region data replication with security controls
- Audit logging for all recovery operations

## Troubleshooting

### Common Issues

1. **Service Extension Not Triggering**: Check function URL configuration and authentication
2. **DR Infrastructure Not Scaling**: Verify IAM permissions for Compute Engine operations
3. **Backup Operations Failing**: Check Backup and DR Service API permissions
4. **Load Balancer Health Checks Failing**: Verify instance startup scripts and firewall rules

### Debug Commands

```bash
# Check service extension logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=dr-orchestrator"

# Monitor instance group operations
gcloud compute operations list --filter="operationType=resize"

# Verify backup vault permissions
gcloud backup-dr backup-vaults get-iam-policy primary-backup-vault --location=${REGION}
```

## Best Practices

### Production Deployment

1. **Testing**: Implement regular DR testing schedules
2. **Monitoring**: Set up comprehensive alerting and dashboards
3. **Documentation**: Maintain runbooks for manual intervention scenarios
4. **Security**: Regular security reviews and access audits
5. **Cost Management**: Monitor and optimize DR infrastructure costs

### Performance Optimization

1. **Service Extension Efficiency**: Optimize failure detection algorithms
2. **Function Cold Starts**: Use minimum instances for critical functions
3. **Backup Scheduling**: Optimize backup windows for minimal performance impact
4. **Network Optimization**: Use Premium Network Service Tier for consistent performance

## Support and Documentation

### Additional Resources

- [Google Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)
- [Service Extensions Overview](https://cloud.google.com/service-extensions/docs/overview)
- [Backup and DR Service Best Practices](https://cloud.google.com/backup-disaster-recovery/docs/best-practices)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Disaster Recovery Planning Guide](https://cloud.google.com/architecture/dr-scenarios-planning-guide)

### Getting Help

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Consult Google Cloud support for platform-specific issues
4. Review Cloud Operations logs for detailed error information

## Contributing

To improve this IaC implementation:
1. Test thoroughly in non-production environments
2. Follow Google Cloud best practices
3. Document any customizations or extensions
4. Submit issues or improvements to the recipe repository