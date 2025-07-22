# Infrastructure as Code for Security Posture Assessment with Security Command Center and Workload Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Security Posture Assessment with Security Command Center and Workload Manager".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Organization-level access for Security Command Center
- Security Command Center Premium or Enterprise tier subscription
- Appropriate IAM permissions:
  - Security Admin
  - Workload Manager Admin
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Service Usage Admin
  - IAM Admin
- Estimated cost: $50-100/month for Security Command Center Premium + compute resources

> **Note**: Security Command Center Premium tier is required for security posture service and custom detectors. Consider starting with a trial subscription to evaluate the solution.

## Quick Start

### Using Infrastructure Manager (Google Cloud)

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses standard Terraform configuration language.

```bash
# Set required environment variables
export PROJECT_ID="your-security-project"
export REGION="us-central1"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)

# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply security-posture-deployment \
    --location=${REGION} \
    --service-account=your-service-account@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},organization_id=${ORGANIZATION_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe security-posture-deployment \
    --location=${REGION}
```

### Using Terraform

Terraform provides multi-cloud infrastructure as code with extensive Google Cloud provider support.

```bash
# Set required environment variables
export PROJECT_ID="your-security-project"
export REGION="us-central1"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)

# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
region = "${REGION}"
organization_id = "${ORGANIZATION_ID}"
security_posture_name = "secure-baseline"
topic_name = "security-events"
function_name = "security-remediation"
EOF

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide a simple, step-by-step deployment approach following the recipe instructions.

```bash
# Set required environment variables
export PROJECT_ID="your-security-project"
export REGION="us-central1"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and success confirmations
```

## Deployment Details

### Infrastructure Manager Configuration

The Infrastructure Manager deployment creates:
- Security Command Center configuration with baseline security posture
- Workload Manager evaluation rules for security compliance
- Pub/Sub topic and subscription for event processing
- Cloud Function for automated remediation
- IAM service accounts and roles
- Cloud Storage bucket for logs and configurations
- Monitoring dashboard for security posture visibility

### Terraform Configuration

The Terraform configuration includes:
- **main.tf**: Core infrastructure resources
- **variables.tf**: Input variables with validation
- **outputs.tf**: Key resource information for verification
- **versions.tf**: Provider and Terraform version constraints

Key resources managed:
- Security Command Center posture and deployment
- Workload Manager evaluation configuration
- Pub/Sub messaging infrastructure
- Cloud Functions for event processing
- IAM roles and service accounts
- Cloud Storage for artifact storage
- Cloud Monitoring dashboard

### Bash Script Deployment

The bash scripts follow the recipe steps:
1. **Environment Setup**: Configure project and enable APIs
2. **Security Command Center**: Enable and configure security postures
3. **Workload Manager**: Deploy custom validation rules
4. **Event Processing**: Create Pub/Sub topic and subscriptions
5. **Remediation Function**: Deploy Cloud Function with remediation logic
6. **Monitoring**: Configure security dashboard and alerts
7. **Automation**: Set up scheduled evaluations and workflows

## Configuration Options

### Common Variables

All implementations support these configuration options:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Google Cloud region | `us-central1` | Yes |
| `organization_id` | Google Cloud organization ID | - | Yes |
| `security_posture_name` | Name for security posture | `secure-baseline` | No |
| `topic_name` | Pub/Sub topic name | `security-events` | No |
| `function_name` | Cloud Function name | `security-remediation` | No |
| `bucket_name` | Storage bucket name | `${project_id}-security-logs` | No |
| `evaluation_schedule` | Workload Manager schedule | `0 */6 * * *` | No |

### Security Configuration

The deployment implements several security best practices:
- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Encrypted Storage**: All data encrypted at rest and in transit
- **Network Security**: VPC-native services with private IP addresses
- **Audit Logging**: Comprehensive logging for all security activities
- **Monitoring**: Real-time alerts for security events and failures

## Validation

After deployment, validate the infrastructure:

### Verify Security Command Center
```bash
# Check Security Command Center status
gcloud scc organizations describe ${ORGANIZATION_ID}

# List security postures
gcloud scc postures list --organization=${ORGANIZATION_ID} --location=global
```

### Verify Workload Manager
```bash
# Check Workload Manager evaluations
gcloud workload-manager evaluations list --location=${REGION}

# Run manual evaluation
gcloud workload-manager evaluations run security-compliance --location=${REGION}
```

### Test Event Processing
```bash
# Publish test message to Pub/Sub
gcloud pubsub topics publish security-events-topic \
    --message='{"category":"TEST_FINDING","severity":"MEDIUM","resourceName":"test-resource"}'

# Check Cloud Function logs
gcloud functions logs read security-remediation-function --limit=10
```

### Monitor Security Dashboard
```bash
# Access monitoring dashboard
echo "Security dashboard: https://console.cloud.google.com/monitoring/dashboards"

# List available dashboards
gcloud monitoring dashboards list --filter="displayName:Security Posture Dashboard"
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete security-posture-deployment \
    --location=${REGION} \
    --delete-policy=DELETE
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

## Customization

### Custom Security Rules

To add custom Workload Manager rules:

1. Edit the `security-validation-rules.yaml` file
2. Add new rules following the Workload Manager schema
3. Redeploy the configuration

Example custom rule:
```yaml
- name: "ensure-vm-labels"
  description: "Verify VMs have required labels"
  type: "COMPUTE_ENGINE"
  severity: "MEDIUM"
  customLogic: |
    resource.labels.environment != null &&
    resource.labels.team != null
```

### Custom Remediation Logic

To extend the Cloud Function remediation logic:

1. Edit the `main.py` file in the function source
2. Add new remediation functions for specific finding types
3. Update the `process_security_event` function to handle new cases
4. Redeploy the function

### Advanced Monitoring

To enhance monitoring and alerting:

1. Create additional monitoring dashboards
2. Configure alerting policies for critical findings
3. Set up notification channels (email, SMS, Slack)
4. Create custom metrics for security posture tracking

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Ensure service account has required IAM roles
   - Verify organization-level permissions for Security Command Center
   - Check API enablement status

2. **Security Command Center Not Available**
   - Confirm Premium/Enterprise tier subscription
   - Verify organization-level access
   - Check billing account status

3. **Workload Manager Evaluation Failures**
   - Review evaluation logs in Cloud Logging
   - Verify resource access permissions
   - Check custom rule syntax

4. **Cloud Function Errors**
   - Review function logs in Cloud Logging
   - Check function memory and timeout settings
   - Verify Pub/Sub message format

### Debugging Commands

```bash
# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:serviceAccount:security-automation@${PROJECT_ID}.iam.gserviceaccount.com"

# View Cloud Function logs
gcloud functions logs read security-remediation-function \
    --limit=50 \
    --format="table(timestamp,message)"

# Check Pub/Sub subscription status
gcloud pubsub subscriptions describe security-events-subscription \
    --format="table(name,deliveryDelay,messageRetentionDuration)"
```

## Cost Optimization

### Resource Optimization

1. **Function Memory**: Adjust Cloud Function memory based on actual usage
2. **Evaluation Frequency**: Optimize Workload Manager evaluation schedule
3. **Log Retention**: Configure appropriate log retention periods
4. **Storage Classes**: Use appropriate storage classes for long-term data

### Cost Monitoring

```bash
# Enable billing export to BigQuery
gcloud alpha billing accounts set-account-budget ${BILLING_ACCOUNT_ID} \
    --budget-file=budget.yaml

# Monitor Security Command Center costs
gcloud logging metrics create security_command_center_usage \
    --description="Security Command Center API usage" \
    --log-filter="resource.type=security_command_center"
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown for solution details
2. **Google Cloud Documentation**: 
   - [Security Command Center](https://cloud.google.com/security-command-center/docs)
   - [Workload Manager](https://cloud.google.com/workload-manager/docs)
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
3. **Provider Documentation**: [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: Google Cloud Community forums and Stack Overflow

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This infrastructure code is provided under the same license as the recipe collection.