# Infrastructure as Code for Implementing Automated Security Compliance Monitoring with Security Command Center and Cloud Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Automated Security Compliance Monitoring with Security Command Center and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Security Command Center Premium or Enterprise tier enabled
- Appropriate IAM permissions for resource creation:
  - Organization Admin or Security Admin (for Security Command Center)
  - Project Editor or Owner
  - Pub/Sub Admin
  - Cloud Functions Admin
  - Workflows Admin
  - Logging Admin
  - Monitoring Admin
- For Terraform: Terraform >= 1.0 installed
- Estimated cost: $50-100/month for small to medium environments

> **Note**: Security Command Center Standard tier has limited features. Premium or Enterprise tier is required for continuous exports and advanced automation capabilities.

## Architecture Overview

This solution creates an automated security compliance monitoring system that includes:

- **Security Command Center**: Real-time threat detection and policy violation monitoring
- **Pub/Sub**: Event-driven messaging for security findings
- **Cloud Functions**: Serverless processing of security events
- **Cloud Workflows**: Orchestration of security response procedures
- **Cloud Logging & Monitoring**: Comprehensive observability and alerting

## Quick Start

### Using Infrastructure Manager

```bash
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/security-compliance \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --git-source-repo=https://github.com/your-org/your-repo.git \
    --git-source-directory=gcp/implementing-automated-security-compliance-monitoring-with-security-command-center-and-cloud-workflows/code/infrastructure-manager

# Check deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/security-compliance
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud projects describe $(gcloud config get-value project)
```

## Configuration Parameters

### Infrastructure Manager Variables

Configure the following parameters in your Infrastructure Manager deployment:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `organization_id`: Your Google Cloud organization ID
- `topic_name`: Pub/Sub topic name for security findings
- `workflow_names`: Names for security response workflows
- `function_name`: Cloud Function name for processing findings

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region
- `zone`: Deployment zone
- `organization_id`: Google Cloud organization ID
- `environment`: Environment name (dev, staging, prod)
- `enable_monitoring`: Enable comprehensive monitoring (default: true)
- `security_notification_email`: Email for security alerts

### Environment Variables for Scripts

Set these environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export ORGANIZATION_ID="your-org-id"
export SECURITY_EMAIL="security-team@company.com"
```

## Deployment Details

### Resources Created

1. **Pub/Sub Infrastructure**:
   - Topic for security findings
   - Subscription for workflow triggers
   - IAM bindings for Security Command Center

2. **Cloud Functions**:
   - Security finding processor function
   - Event-driven trigger configuration
   - IAM service account with minimal permissions

3. **Cloud Workflows**:
   - High-severity response workflow
   - Medium-severity response workflow
   - Low-severity response workflow
   - Execution service account

4. **Security Command Center**:
   - Notification configuration
   - Pub/Sub integration
   - Finding export configuration

5. **Monitoring & Logging**:
   - Log-based metrics
   - Alert policies
   - Notification channels
   - Custom dashboard

### Security Considerations

- All resources follow Google Cloud security best practices
- Service accounts use principle of least privilege
- Security Command Center notifications are encrypted in transit
- Cloud Functions use secure environment variables
- Workflows implement proper error handling and logging

### Cost Optimization

- Functions scale to zero when not processing events
- Pub/Sub charges only for messages processed
- Workflows charge per execution step
- Monitoring and logging follow standard pricing
- Security Command Center costs depend on tier selected

## Validation & Testing

### Post-Deployment Verification

1. **Check Pub/Sub Topic**:
   ```bash
   gcloud pubsub topics describe $(terraform output -raw pubsub_topic_name)
   ```

2. **Verify Cloud Functions**:
   ```bash
   gcloud functions list --filter="name:security-processor"
   ```

3. **Test Workflow Execution**:
   ```bash
   gcloud workflows run high-severity-workflow \
       --location=us-central1 \
       --data='{"finding":{"name":"test-finding","severity":"HIGH"}}'
   ```

4. **Check Security Command Center Integration**:
   ```bash
   gcloud scc notifications list --organization=$ORGANIZATION_ID
   ```

### Testing Security Response

The deployment includes test scripts to validate the complete security response pipeline:

```bash
# Run end-to-end test
cd scripts/
./test-security-pipeline.sh

# Generate test security finding
./generate-test-finding.sh

# Verify workflow execution
./check-workflow-status.sh
```

## Troubleshooting

### Common Issues

1. **Security Command Center Tier**: Ensure Premium or Enterprise tier is enabled
2. **Organization Permissions**: Verify Organization Admin access for SCC configuration
3. **API Enablement**: All required APIs must be enabled before deployment
4. **Service Account Permissions**: Check IAM bindings for service accounts

### Debug Commands

```bash
# Check function logs
gcloud functions logs read security-processor --gen2 --region=us-central1

# View workflow executions
gcloud workflows executions list --workflow=high-severity-workflow --location=us-central1

# Monitor Pub/Sub messages
gcloud pubsub subscriptions pull security-findings-sub --auto-ack --limit=10
```

## Customization

### Extending Security Workflows

1. **Add Custom Remediation Actions**:
   - Modify workflow YAML files in the workflows directory
   - Implement additional Cloud Functions for specific remediation tasks
   - Update IAM permissions for new service accounts

2. **Custom Notification Channels**:
   - Add Slack, PagerDuty, or other integrations
   - Modify notification functions to support additional channels
   - Configure alert policies for different severity levels

3. **Advanced Filtering**:
   - Customize Security Command Center notification filters
   - Implement finding classification logic in Cloud Functions
   - Add machine learning models for threat scoring

### Integration with External Systems

- **SIEM Integration**: Modify workflows to send findings to external SIEM systems
- **Ticketing Systems**: Add workflow steps to create tickets in ServiceNow, Jira, etc.
- **Compliance Reporting**: Extend monitoring to generate compliance reports

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/security-compliance
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

After running automated cleanup, verify these resources are removed:

```bash
# Check remaining resources
gcloud pubsub topics list --filter="name:security-findings"
gcloud functions list --filter="name:security-processor"
gcloud workflows list --filter="name:*-severity-workflow"
gcloud logging metrics list --filter="name:security_*"
```

## Monitoring & Maintenance

### Regular Maintenance Tasks

1. **Update Workflow Logic**: Review and update security response procedures quarterly
2. **Review IAM Permissions**: Audit service account permissions monthly
3. **Monitor Costs**: Track Security Command Center and associated service costs
4. **Test Response Procedures**: Conduct regular security response drills

### Performance Monitoring

- Monitor function execution times and error rates
- Track workflow success/failure rates
- Review Pub/Sub message processing delays
- Analyze security finding response times

## Support

### Documentation References

- [Security Command Center Documentation](https://cloud.google.com/security-command-center/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Google Cloud Status page for service issues
3. Consult the original recipe documentation
4. Contact your Google Cloud support team for enterprise issues

### Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow Google Cloud resource naming conventions
3. Update documentation for any configuration changes
4. Validate security implications of modifications