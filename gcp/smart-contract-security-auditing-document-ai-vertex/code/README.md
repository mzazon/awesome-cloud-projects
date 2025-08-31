# Infrastructure as Code for Smart Contract Security Auditing with Document AI and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Contract Security Auditing with Document AI and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Document AI Editor
  - Vertex AI User
  - Cloud Functions Admin
  - Storage Admin
  - Service Usage Admin
- Python 3.9+ (for Cloud Functions runtime)
- Terraform >= 1.0 (if using Terraform implementation)

## Architecture Overview

This solution deploys:
- Cloud Storage bucket for contract artifacts and audit reports
- Document AI processor for contract text extraction
- Cloud Function for security analysis orchestration
- Vertex AI integration for vulnerability detection
- IAM roles and permissions for secure service communication

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/smart-contract-audit \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/inputs.yaml"

# Monitor deployment
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/smart-contract-audit
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployment
./scripts/test-deployment.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml` to customize:

```yaml
project_id: "your-project-id"
region: "us-central1"
bucket_name_suffix: "unique-suffix"
function_memory: "1GB"
function_timeout: "540s"
document_ai_location: "us-central1"
```

### Terraform Variables

Customize deployment by modifying `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
bucket_name_suffix = "unique-suffix"
function_memory = 1024
function_timeout = 540
labels = {
  environment = "production"
  team = "security"
}
```

### Script Variables

Export environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BUCKET_NAME_SUFFIX="unique-suffix"
export FUNCTION_MEMORY="1GB"
export FUNCTION_TIMEOUT="540s"
```

## Testing the Deployment

### Upload Sample Contract

```bash
# Create a sample vulnerable contract
cat > vulnerable_contract.sol << 'EOF'
pragma solidity ^0.8.0;

contract VulnerableBank {
    mapping(address => uint256) public balances;
    
    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount);
        
        // Reentrancy vulnerability
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success);
        
        balances[msg.sender] -= _amount;
    }
}
EOF

# Upload to trigger analysis
gsutil cp vulnerable_contract.sol gs://contract-audit-${BUCKET_NAME_SUFFIX}/contracts/
```

### Check Analysis Results

```bash
# Wait for processing (30-60 seconds)
sleep 60

# Check for audit report
gsutil ls gs://contract-audit-${BUCKET_NAME_SUFFIX}/audit-reports/

# Download and view results
gsutil cp gs://contract-audit-${BUCKET_NAME_SUFFIX}/audit-reports/vulnerable_contract_security_audit.json ./
cat vulnerable_contract_security_audit.json | jq .
```

### Monitor Function Logs

```bash
# View Cloud Function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=contract-security-analyzer" \
    --limit=10 \
    --format="value(timestamp,severity,textPayload)"
```

## Cost Considerations

### Estimated Monthly Costs (Light Usage)

- **Cloud Storage**: $0.02/GB for standard storage
- **Document AI**: $1.50 per 1,000 pages processed
- **Vertex AI**: $0.002 per 1,000 characters for Gemini Pro
- **Cloud Functions**: $0.40 per million invocations + $0.0000025 per GB-second
- **Total Estimated**: $10-50/month for moderate usage

### Cost Optimization Tips

- Enable Cloud Storage lifecycle policies for audit reports
- Use Cloud Functions concurrency limits to control costs
- Monitor Document AI usage in Cloud Console
- Set up billing alerts for unexpected usage

## Security Considerations

### IAM Best Practices

- Service accounts use least privilege principle
- Cloud Function has minimal required permissions
- Document AI processor access is scoped appropriately
- Vertex AI access limited to required models

### Data Protection

- Contract files encrypted at rest in Cloud Storage
- Audit reports protected by Cloud IAM
- No sensitive data logged in Cloud Functions
- Network traffic encrypted in transit

### Compliance

- Supports audit logging through Cloud Audit Logs
- Data residency controlled through region selection
- Access controls meet enterprise security requirements
- Integration with Cloud Security Command Center available

## Troubleshooting

### Common Issues

**Cloud Function timeout errors:**
```bash
# Increase timeout in configuration
gcloud functions deploy contract-security-analyzer --timeout=540s
```

**Document AI quota exceeded:**
```bash
# Check quota usage
gcloud logging read "resource.type=documentai_processor" --limit=5
```

**Vertex AI permission errors:**
```bash
# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} --format="table(bindings.role,bindings.members)"
```

**Storage access denied:**
```bash
# Check bucket permissions
gsutil iam get gs://contract-audit-${BUCKET_NAME_SUFFIX}
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Update function with debug environment variable
gcloud functions deploy contract-security-analyzer \
    --set-env-vars=DEBUG=true,LOG_LEVEL=DEBUG
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/smart-contract-audit

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
gcloud functions list --regions=${REGION}
gsutil ls -p ${PROJECT_ID}
```

### Manual Cleanup (if needed)

```bash
# Delete remaining resources manually
gcloud functions delete contract-security-analyzer --region=${REGION} --quiet
gsutil -m rm -r gs://contract-audit-*
gcloud documentai processors delete projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID} --quiet

# Disable APIs if no longer needed
gcloud services disable documentai.googleapis.com
gcloud services disable aiplatform.googleapis.com
gcloud services disable cloudfunctions.googleapis.com
```

## Customization

### Adding New Vulnerability Patterns

Edit the Cloud Function source in `scripts/function-source/main.py` to add custom security checks:

```python
# Add custom vulnerability patterns
custom_patterns = {
    "hardcoded_private_keys": r"(private.*key|secret.*key)\s*=\s*['\"][0-9a-fA-F]{64}['\"]",
    "unsafe_delegatecall": r"delegatecall\s*\(",
    "unprotected_selfdestruct": r"selfdestruct\s*\([^)]*\)\s*;",
}
```

### Extending Analysis Models

Configure additional Vertex AI models for specialized analysis:

```python
# Use different models for specific contract types
model_config = {
    "defi_contracts": "gemini-1.5-pro",
    "nft_contracts": "gemini-1.0-pro",
    "governance_contracts": "gemini-1.5-pro"
}
```

### Integration with CI/CD

Add webhook integration for automated contract analysis:

```yaml
# Cloud Build configuration
steps:
  - name: 'gcr.io/cloud-builders/gsutil'
    args: ['cp', 'contracts/*.sol', 'gs://contract-audit-${_BUCKET_SUFFIX}/contracts/']
  - name: 'gcr.io/cloud-builders/gcloud'
    args: ['functions', 'call', 'contract-security-analyzer']
```

## Support and Documentation

### Additional Resources

- [Google Cloud Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Vertex AI Generative AI Guide](https://cloud.google.com/vertex-ai/docs/generative-ai)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Smart Contract Security Best Practices](https://consensys.github.io/smart-contract-best-practices/)

### Getting Help

- For infrastructure issues: Check Google Cloud Console logs and status page
- For security analysis accuracy: Review Vertex AI model documentation
- For cost optimization: Use Google Cloud Billing reports and recommendations
- For general support: Consult the original recipe documentation

### Contributing

To enhance this infrastructure code:

1. Test changes in a development environment
2. Validate security configurations
3. Update documentation accordingly
4. Consider backward compatibility with existing deployments

---

**Note**: This infrastructure deploys AI-powered security analysis tools. Always validate AI-generated security findings with human expert review for production smart contracts.