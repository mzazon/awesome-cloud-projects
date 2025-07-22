# Infrastructure as Code for Code Review Automation with CodeGuru

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Code Review Automation with CodeGuru".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Git client installed and configured
- Appropriate AWS permissions for:
  - CodeGuru Reviewer and Profiler
  - CodeCommit repository management
  - IAM role creation and management
- Java 8+ or Python 3.8+ for profiling applications
- Understanding of code review processes and performance optimization
- Estimated cost: $10-50/month for CodeGuru services depending on repository size and profiling duration

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name codeguru-automation-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=RepositoryName,ParameterValue=my-codeguru-repo \
                 ParameterKey=ProfilerGroupName,ParameterValue=my-profiler-group \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name codeguru-automation-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name codeguru-automation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy CodeGuruAutomationStack \
    --parameters repositoryName=my-codeguru-repo \
    --parameters profilerGroupName=my-profiler-group

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy CodeGuruAutomationStack \
    -c repository_name=my-codeguru-repo \
    -c profiler_group_name=my-profiler-group

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="repository_name=my-codeguru-repo" \
               -var="profiler_group_name=my-profiler-group"

# Apply the configuration
terraform apply -var="repository_name=my-codeguru-repo" \
                -var="profiler_group_name=my-profiler-group"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export REPOSITORY_NAME=my-codeguru-repo
export PROFILER_GROUP_NAME=my-profiler-group

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Parameters

### Required Parameters
- `repository_name` / `RepositoryName`: Name for the CodeCommit repository
- `profiler_group_name` / `ProfilerGroupName`: Name for the CodeGuru Profiler group

### Optional Parameters
- `aws_region`: AWS region for deployment (defaults to current CLI region)
- `enable_reviewer`: Enable CodeGuru Reviewer (default: true)
- `enable_profiler`: Enable CodeGuru Profiler (default: true)

## Post-Deployment Setup

After deploying the infrastructure, follow these steps to complete the setup:

### 1. Clone the Repository
```bash
# Get repository clone URL from outputs
CLONE_URL=$(aws codecommit get-repository \
    --repository-name <your-repository-name> \
    --query 'repositoryMetadata.cloneUrlHttp' --output text)

# Clone the repository
git clone $CLONE_URL
cd <your-repository-name>
```

### 2. Add Sample Code
```bash
# Create sample Java application with issues for CodeGuru to analyze
mkdir -p src/main/java/com/example
cat > src/main/java/com/example/DatabaseManager.java << 'EOF'
package com.example;

import java.sql.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.List;
import java.util.ArrayList;

public class DatabaseManager {
    private static ConcurrentHashMap<String, Connection> connections = new ConcurrentHashMap<>();
    private static final String DB_URL = "jdbc:mysql://localhost:3306/mydb";
    private static final String USER = "admin";
    private static final String PASS = "password123"; // Hardcoded credential
    
    public List<String> executeQuery(String sql) throws SQLException {
        Connection conn = DriverManager.getConnection(DB_URL, USER, PASS);
        Statement stmt = conn.createStatement();
        ResultSet rs = stmt.executeQuery(sql); // SQL injection potential
        
        List<String> results = new ArrayList<>();
        while (rs.next()) {
            results.add(rs.getString(1));
        }
        
        return results; // Resources not closed
    }
}
EOF

# Commit the code
git add .
git commit -m "Initial commit with sample code for CodeGuru analysis"
git push origin main
```

### 3. Trigger Code Review
```bash
# Get repository association ARN from outputs
ASSOCIATION_ARN=$(aws codeguru-reviewer list-repository-associations \
    --query 'RepositoryAssociationSummaries[?Repository.Name==`<your-repository-name>`].AssociationArn' \
    --output text)

# Create full repository analysis
aws codeguru-reviewer create-code-review \
    --name "initial-analysis-$(date +%Y%m%d-%H%M%S)" \
    --repository-association-arn $ASSOCIATION_ARN \
    --type '{"RepositoryAnalysis": {"RepositoryHead": {"BranchName": "main"}}}'
```

### 4. Monitor Code Review Progress
```bash
# List recent code reviews
aws codeguru-reviewer list-code-reviews \
    --repository-association-arn $ASSOCIATION_ARN

# Check recommendations (replace CODE_REVIEW_ARN with actual ARN)
aws codeguru-reviewer list-recommendations \
    --code-review-arn <CODE_REVIEW_ARN>
```

### 5. Set Up Application Profiling (Optional)
```bash
# Set environment variables for profiling
export PROFILING_GROUP_NAME=<your-profiler-group-name>
export AWS_CODEGURU_PROFILER_TARGET_REGION=$(aws configure get region)
export AWS_CODEGURU_PROFILER_ENABLED=true

# Run your Java application with profiling agent
java -javaagent:codeguru-profiler-java-agent-standalone-1.2.1.jar \
     -Dcom.amazonaws.codeguru.profiler.enabled=true \
     -Dcom.amazonaws.codeguru.profiler.application.name=$PROFILING_GROUP_NAME \
     your-application.jar
```

## Validation & Testing

### Verify Repository Association
```bash
# Check that CodeGuru Reviewer is associated with the repository
aws codeguru-reviewer list-repository-associations \
    --query 'RepositoryAssociationSummaries[?State==`Associated`]'
```

### Test Code Quality Gates
```bash
# The deployment includes quality gate scripts in the repository
# Run the quality check script (after code review completes)
./check_code_quality.sh <CODE_REVIEW_ARN>
```

### Monitor Profiling Data
```bash
# Check profiling group status
aws codeguru-profiler describe-profiling-group \
    --profiling-group-name <your-profiler-group-name>

# List recent profile times
aws codeguru-profiler list-profile-times \
    --profiling-group-name <your-profiler-group-name> \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

## Cleanup

### Using CloudFormation
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name codeguru-automation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name codeguru-automation-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy CodeGuruAutomationStack
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy CodeGuruAutomationStack
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="repository_name=my-codeguru-repo" \
                  -var="profiler_group_name=my-profiler-group"
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm cleanup completion
./scripts/status.sh
```

## Customization

### Repository Configuration
Modify the repository settings by updating the parameters in your chosen IaC implementation:

- Repository description and tags
- Branch protection rules
- Trigger configurations

### CodeGuru Reviewer Settings
Customize the reviewer configuration:

- Analysis scope (file patterns to include/exclude)
- Recommendation severity thresholds
- Integration with external tools

### Profiling Group Settings
Adjust profiling parameters:

- Sampling rates
- Data retention periods
- Agent configuration options

### Quality Gates
Customize the automated quality gates by modifying the included scripts:

- Severity thresholds for blocking deployments
- Custom recommendation filters
- Integration with CI/CD pipelines

## Monitoring and Troubleshooting

### Common Issues

1. **Repository Association Failed**
   - Check IAM permissions for CodeGuru Reviewer service role
   - Verify repository exists and is accessible
   - Ensure region consistency across resources

2. **No Profiling Data**
   - Verify profiling agent configuration
   - Check application runtime environment variables
   - Confirm profiling group is active

3. **Code Review Timeout**
   - Large repositories may take longer to analyze
   - Check repository association status
   - Verify branch exists and has commits

### Monitoring Commands
```bash
# Monitor CodeGuru service quotas
aws service-quotas list-service-quotas --service-code codeguru-reviewer

# Check CloudWatch metrics for CodeGuru
aws cloudwatch get-metric-statistics \
    --namespace AWS/CodeGuru/Reviewer \
    --metric-name RepositoryAssociations \
    --start-time $(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 3600 \
    --statistics Sum
```

## Integration Examples

### GitHub Actions Integration
```yaml
# .github/workflows/codeguru.yml
name: CodeGuru Analysis
on:
  pull_request:
    branches: [ main ]

jobs:
  code-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Run CodeGuru Analysis
        run: ./scripts/integrate_codeguru_ci.sh $ASSOCIATION_ARN $GITHUB_HEAD_REF
```

### Jenkins Pipeline Integration
```groovy
pipeline {
    agent any
    stages {
        stage('CodeGuru Analysis') {
            steps {
                script {
                    sh './scripts/integrate_codeguru_ci.sh ${ASSOCIATION_ARN} ${BRANCH_NAME}'
                }
            }
        }
    }
}
```

## Cost Optimization

### CodeGuru Reviewer Costs
- Charged per 100 lines of code analyzed
- First 90 days include 500,000 lines of code per month at no charge
- Monitor usage through AWS Billing Dashboard

### CodeGuru Profiler Costs
- Charged per agent-hour of profiling
- First 36 agent-hours per month at no charge
- Use sampling to reduce costs for high-volume applications

### Cost Monitoring
```bash
# Check CodeGuru usage and costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Security Considerations

### IAM Best Practices
- The generated IAM roles follow least privilege principles
- Regularly review and rotate access keys
- Use IAM roles for EC2 instances when possible

### Data Protection
- CodeGuru processes source code data - ensure compliance with data protection policies
- Review AWS data processing agreements
- Consider data residency requirements when choosing regions

### Network Security
- CodeCommit supports VPC endpoints for private connectivity
- Configure security groups appropriately for profiled applications
- Use AWS PrivateLink when available

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../building-code-review-automation-with-codeguru.md)
- [AWS CodeGuru Reviewer User Guide](https://docs.aws.amazon.com/codeguru/latest/reviewer-ug/)
- [AWS CodeGuru Profiler User Guide](https://docs.aws.amazon.com/codeguru/latest/profiler-ug/)
- [AWS CodeCommit User Guide](https://docs.aws.amazon.com/codecommit/latest/userguide/)

## Additional Resources

- [CodeGuru Reviewer API Reference](https://docs.aws.amazon.com/codeguru/latest/reviewer-api/)
- [CodeGuru Profiler API Reference](https://docs.aws.amazon.com/codeguru/latest/profiler-api/)
- [AWS Well-Architected Tool](https://aws.amazon.com/well-architected-tool/)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)