# Infrastructure as Code for Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's recommended infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- IAM permissions for:
  - Security Admin
  - Database Admin
  - Workflows Admin
  - Asset Inventory Viewer
  - Service Account Admin
  - BigQuery Admin
  - Cloud Functions Admin
- Terraform CLI (version 1.5+) if using Terraform implementation
- Basic understanding of database governance and compliance frameworks

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply \
    projects/PROJECT_ID/locations/REGION/deployments/db-governance \
    --service-account=projects/PROJECT_ID/serviceAccounts/SERVICE_ACCOUNT \
    --git-source-repo=https://github.com/your-repo/path \
    --git-source-directory=gcp/centralized-database-fleet-governance-database-center-asset-inventory/code/infrastructure-manager/ \
    --git-source-ref=main \
    --input-values=project_id=PROJECT_ID,region=REGION
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts to configure project ID and region
```

## Architecture Overview

This infrastructure deploys a comprehensive database governance solution that includes:

### Core Components

- **Database Fleet**: Sample Cloud SQL, Spanner, and Bigtable instances for governance testing
- **Database Center**: AI-powered fleet management with Gemini integration
- **Cloud Asset Inventory**: Automated resource discovery and compliance monitoring
- **Cloud Workflows**: Orchestration engine for governance automation
- **Cloud Monitoring**: Real-time alerting and metrics collection

### Data and Analytics Layer

- **BigQuery Dataset**: Asset inventory exports and compliance reporting
- **Cloud Storage**: Compliance reports and audit trails
- **Pub/Sub**: Real-time asset change notifications
- **Cloud Functions**: Automated compliance reporting and remediation

### AI and Automation

- **Gemini AI Integration**: Natural language governance queries and recommendations
- **Cloud Scheduler**: Automated governance checks every 6 hours
- **Custom Dashboards**: Fleet overview and compliance visualizations

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | No |
| `random_suffix` | Unique suffix for resources | Auto-generated | No |
| `enable_deletion_protection` | Enable deletion protection for databases | `true` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud project ID | `string` | - | Yes |
| `region` | Primary deployment region | `string` | `us-central1` | No |
| `zone` | Primary deployment zone | `string` | `us-central1-a` | No |
| `random_suffix` | Unique suffix for resources | `string` | Auto-generated | No |
| `notification_email` | Email for governance alerts | `string` | - | Yes |
| `scheduler_frequency` | Governance check frequency | `string` | `0 */6 * * *` | No |

### Example Terraform Configuration

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
notification_email = "admin@yourcompany.com"
scheduler_frequency = "0 */4 * * *"  # Every 4 hours
EOF

# Deploy with custom configuration
terraform apply -var-file="terraform.tfvars"
```

## Post-Deployment Steps

### 1. Access Database Center

After deployment, access the Database Center dashboard:

```bash
echo "Navigate to Database Center:"
echo "https://console.cloud.google.com/database-center?project=YOUR_PROJECT_ID"
```

The dashboard will show:
- All discovered database instances
- AI-powered health insights
- Gemini chat interface for natural language queries
- Security recommendations

### 2. Verify Asset Inventory Integration

Check that asset inventory is collecting database metadata:

```bash
# Query asset inventory in BigQuery
bq query --use_legacy_sql=false \
"SELECT asset_type, COUNT(*) as count 
 FROM \`YOUR_PROJECT_ID.database_governance.asset_inventory\` 
 WHERE asset_type LIKE '%Instance' 
 GROUP BY asset_type"
```

### 3. Test Governance Automation

Verify that governance workflows are functioning:

```bash
# Check workflow executions
gcloud workflows executions list \
    --workflow=database-governance-workflow \
    --limit=5

# Manually trigger compliance report
curl -X GET "https://REGION-PROJECT_ID.cloudfunctions.net/compliance-reporter?project_id=PROJECT_ID"
```

### 4. Configure Custom Governance Policies

The deployment includes basic governance policies. Customize them by:

1. Editing the workflow definition in `governance-workflow.yaml`
2. Updating compliance validation logic in the Cloud Function
3. Adding custom monitoring metrics and alerts
4. Configuring additional notification channels

## Monitoring and Observability

### Key Metrics

The solution automatically creates these custom metrics:

- `database_compliance_score`: Overall fleet compliance percentage
- `governance_events`: Count of governance automation events
- Database-specific health and performance metrics

### Dashboards

Access monitoring dashboards:

```bash
echo "Cloud Monitoring Dashboard:"
echo "https://console.cloud.google.com/monitoring/dashboards?project=YOUR_PROJECT_ID"
```

### Alerting

Governance alerts are automatically configured for:
- Low compliance scores (< 80%)
- Database security violations
- Governance workflow failures
- Asset inventory export issues

## Gemini AI Integration

### Sample Governance Queries

Use these queries in the Database Center Gemini chat interface:

1. **Security Assessment**: "Show me all databases without backup enabled"
2. **Compliance Check**: "Which Cloud SQL instances have public IP access?"
3. **Fleet Overview**: "What are the top security recommendations for my database fleet?"
4. **Performance Insights**: "Which databases have performance issues?"
5. **Cost Optimization**: "Recommend cost optimization strategies for my database fleet"

### Custom Query Examples

```bash
# Programmatic interaction with governance insights
gcloud ai-platform predict \
    --model=governance-insights \
    --json-instances='{"query": "Analyze my database fleet security posture"}'
```

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure service account has all required roles
2. **API Enablement**: Verify all required APIs are enabled
3. **Resource Quotas**: Check project quotas for database instances
4. **Network Configuration**: Ensure proper VPC and firewall settings

### Debug Commands

```bash
# Check service account permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:db-governance-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com"

# Verify API enablement
gcloud services list --enabled --filter="name:cloudasset.googleapis.com OR name:workflows.googleapis.com"

# Check workflow logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=compliance-reporter" \
    --limit=10 \
    --format="value(timestamp,textPayload)"
```

### Recovery Procedures

If deployment fails or becomes corrupted:

1. **Partial Cleanup**: Use the destroy script with `--partial` flag
2. **State Recovery**: For Terraform, use `terraform import` for existing resources
3. **Manual Cleanup**: Remove resources individually via Cloud Console
4. **Fresh Deployment**: Clean project and redeploy from scratch

## Security Considerations

### IAM Best Practices

The deployment follows least privilege principles:

- Service accounts have minimal required permissions
- Database instances use private IPs where possible
- Encryption at rest enabled for all data stores
- Regular credential rotation configured

### Network Security

- VPC-native clusters for secure communication
- Private Google Access enabled
- Cloud Armor protection for public endpoints
- Network security policies for database access

### Data Protection

- Backup retention policies configured
- Point-in-time recovery enabled
- Encryption keys managed by Cloud KMS
- Audit logging for all database operations

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/PROJECT_ID/locations/REGION/deployments/db-governance
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

After automated cleanup, verify all resources are removed:

```bash
# Check for remaining database instances
gcloud sql instances list
gcloud spanner instances list
gcloud bigtable instances list

# Check for remaining storage resources
gsutil ls gs://db-governance-assets-*
bq ls -d YOUR_PROJECT_ID:database_governance

# Check for remaining IAM resources
gcloud iam service-accounts list --filter="email:db-governance-sa@*"
```

## Cost Optimization

### Resource Sizing

The default deployment uses minimal resource sizes suitable for testing:

- Cloud SQL: `db-f1-micro` instances
- Spanner: 1 node regional configuration
- Bigtable: Development instance type
- Cloud Functions: 256MB memory allocation

### Production Sizing Recommendations

For production deployments, consider:

- Cloud SQL: `db-custom-2-4096` or higher
- Spanner: 3+ nodes for high availability
- Bigtable: Production instance type with autoscaling
- Cloud Functions: 512MB+ memory for complex governance logic

### Cost Monitoring

Monitor costs using:

```bash
# Check current spend
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID

# Set up budget alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Database Governance Budget" \
    --budget-amount=100USD
```

## Customization

### Adding New Database Types

To extend governance to additional database types:

1. Update asset inventory filters in `main.tf` or `main.yaml`
2. Add validation logic in governance workflow
3. Update BigQuery schema for new asset types
4. Configure monitoring for new database metrics

### Custom Compliance Policies

Implement organization-specific policies by:

1. Modifying the governance workflow YAML
2. Adding custom validation functions
3. Updating compliance scoring algorithms
4. Configuring policy-specific alerts

### Integration with External Systems

Connect with enterprise systems:

1. Configure webhook endpoints for ITSM integration
2. Set up API gateways for external monitoring tools
3. Implement custom connectors for audit systems
4. Configure SAML/OIDC for single sign-on

## Support

### Documentation Resources

- [Database Center Documentation](https://cloud.google.com/database-center/docs)
- [Cloud Asset Inventory Documentation](https://cloud.google.com/asset-inventory/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Community Support

- Google Cloud Community Forums
- Stack Overflow (tags: google-cloud-platform, database-center)
- GitHub Issues for Terraform provider

### Professional Support

For production deployments, consider:
- Google Cloud Professional Services
- Certified Google Cloud Partners
- Enterprise Support subscriptions

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's official documentation.