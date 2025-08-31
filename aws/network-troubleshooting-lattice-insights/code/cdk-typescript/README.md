# Network Troubleshooting with VPC Lattice and Network Insights - CDK TypeScript

This CDK TypeScript application deploys a comprehensive network troubleshooting platform that combines VPC Lattice service mesh monitoring with automated path analysis and proactive alerting.

## Architecture Overview

The application creates:

- **VPC Lattice Service Network**: Service mesh infrastructure for application-level networking
- **EC2 Test Instance**: Sample workload for network analysis and testing
- **CloudWatch Monitoring**: Dashboards, alarms, and log groups for comprehensive observability
- **VPC Reachability Analyzer Automation**: Systems Manager document for automated network path analysis
- **Lambda Function**: Automated response to network issues detected by CloudWatch alarms
- **SNS Topic**: Notification system for network alerts and incident response
- **IAM Roles**: Least privilege security roles for automation and Lambda execution

## Prerequisites

- AWS CDK v2.147.0 or later
- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- TypeScript knowledge for customization

## Required AWS Permissions

Your AWS credentials need permissions for:
- VPC Lattice (create service networks, associations)
- EC2 (create instances, security groups, network insights)
- CloudWatch (create dashboards, alarms, log groups)
- Lambda (create functions, manage permissions)
- SNS (create topics, subscriptions)
- IAM (create roles, attach policies)
- Systems Manager (create automation documents)

## Quick Start

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if first time using CDK in this account/region):
   ```bash
   npx cdk bootstrap
   ```

3. **Deploy the Stack**:
   ```bash
   npx cdk deploy
   ```

4. **Verify Deployment**:
   ```bash
   # Check stack outputs
   npx cdk list
   aws cloudformation describe-stacks --stack-name NetworkTroubleshootingStack
   ```

## Customization

### Environment Variables

You can customize the deployment by setting environment variables:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-west-2
npx cdk deploy
```

### Context Parameters

Use CDK context for additional customization:

```bash
npx cdk deploy -c account=123456789012 -c region=us-west-2
```

### Stack Properties

Modify the stack properties in `app.ts`:

```typescript
new NetworkTroubleshootingStack(app, 'NetworkTroubleshootingStack', {
  env: {
    account: 'your-account-id',
    region: 'your-preferred-region',
  },
  // Add custom tags
  tags: {
    Environment: 'Production',
    Team: 'NetworkOps',
  },
});
```

## Testing the Solution

### Manual Network Analysis

1. **Trigger Automation Manually**:
   ```bash
   # Get stack outputs
   AUTOMATION_DOC=$(aws cloudformation describe-stacks \
     --stack-name NetworkTroubleshootingStack \
     --query 'Stacks[0].Outputs[?OutputKey==`AutomationDocumentName`].OutputValue' \
     --output text)
   
   AUTOMATION_ROLE=$(aws cloudformation describe-stacks \
     --stack-name NetworkTroubleshootingStack \
     --query 'Stacks[0].Outputs[?OutputKey==`AutomationRoleArn`].OutputValue' \
     --output text)
   
   INSTANCE_ID=$(aws cloudformation describe-stacks \
     --stack-name NetworkTroubleshootingStack \
     --query 'Stacks[0].Outputs[?OutputKey==`TestInstanceId`].OutputValue' \
     --output text)
   
   # Execute network analysis
   aws ssm start-automation-execution \
     --document-name ${AUTOMATION_DOC} \
     --parameters \
       "SourceId=${INSTANCE_ID},DestinationId=${INSTANCE_ID},AutomationAssumeRole=${AUTOMATION_ROLE}"
   ```

2. **Test Lambda Function**:
   ```bash
   # Get Lambda function name
   LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
     --stack-name NetworkTroubleshootingStack \
     --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionArn`].OutputValue' \
     --output text | cut -d: -f7)
   
   # Create test event
   cat > test-event.json << 'EOF'
   {
     "Records": [
       {
         "EventSource": "aws:sns",
         "Sns": {
           "Message": "{\"AlarmName\":\"VPCLattice-HighErrorRate-test\",\"NewStateValue\":\"ALARM\"}"
         }
       }
     ]
   }
   EOF
   
   # Invoke function
   aws lambda invoke \
     --function-name ${LAMBDA_FUNCTION} \
     --payload file://test-event.json \
     response.json
   
   cat response.json
   ```

### Monitor in CloudWatch

1. **Access Dashboard**:
   - Use the dashboard URL from stack outputs
   - Monitor VPC Lattice performance metrics
   - View response code distributions

2. **Check Alarm Status**:
   ```bash
   aws cloudwatch describe-alarms \
     --alarm-name-prefix "VPCLattice-"
   ```

## Cost Considerations

This deployment creates billable resources:

- **EC2 Instance**: t3.micro (~$8-10/month)
- **VPC Lattice**: Service network charges + data processing
- **CloudWatch**: Dashboards, alarms, and log storage
- **Lambda**: Pay per invocation (typically < $1/month for testing)
- **SNS**: Pay per notification (minimal for testing)

## Cleanup

To avoid ongoing charges, destroy the stack:

```bash
npx cdk destroy
```

Confirm destruction when prompted. This will remove all resources created by the stack.

## Troubleshooting

### Common Issues

1. **Bootstrap Required**:
   ```
   Error: This stack uses assets, so the toolkit stack must be deployed
   ```
   Solution: Run `npx cdk bootstrap`

2. **Permission Denied**:
   ```
   Error: User is not authorized to perform: iam:CreateRole
   ```
   Solution: Ensure your AWS credentials have sufficient IAM permissions

3. **VPC Not Found**:
   ```
   Error: Cannot find default VPC
   ```
   Solution: Create a default VPC or modify the code to use a specific VPC ID

### Debug Mode

Enable verbose logging:

```bash
npx cdk deploy --verbose
```

## Security Considerations

This solution implements AWS security best practices:

- **Least Privilege IAM**: Roles have minimal required permissions
- **Security Groups**: Restrictive ingress rules for EC2 instances
- **Encryption**: CloudWatch logs encrypted at rest
- **Resource Tagging**: All resources tagged for governance

## Extension Ideas

1. **Multi-Region Support**: Deploy across multiple regions for global monitoring
2. **Custom Metrics**: Add application-specific network performance indicators
3. **Integration with External Systems**: Connect to ITSM or communication platforms
4. **Advanced Analytics**: Use machine learning for predictive network analysis
5. **Compliance Reporting**: Generate network security compliance reports

## Support

For issues with this CDK application:

1. Check the AWS CDK documentation: https://docs.aws.amazon.com/cdk/
2. Review CloudFormation events in the AWS Console
3. Check CloudWatch logs for Lambda function errors
4. Refer to the original recipe documentation

## Contributing

To contribute improvements to this CDK application:

1. Follow TypeScript and CDK best practices
2. Add appropriate unit tests
3. Update documentation for any changes
4. Ensure security best practices are maintained