# Automated File Lifecycle Management with Amazon FSx and Lambda - CDK TypeScript

This CDK TypeScript application deploys an automated file lifecycle management solution using Amazon FSx for OpenZFS with intelligent tiering capabilities, Lambda functions for automation, and comprehensive monitoring.

## Architecture

The solution creates:

- **Amazon FSx for OpenZFS**: High-performance shared file system with SSD storage and intelligent read caching
- **Lambda Functions**: Three functions for lifecycle policy management, cost reporting, and alert handling
- **EventBridge Rules**: Automated scheduling for periodic analysis and reporting
- **CloudWatch Alarms**: Real-time monitoring with configurable thresholds
- **SNS Topic**: Notification system for alerts and recommendations
- **S3 Bucket**: Storage for cost optimization reports
- **CloudWatch Dashboard**: Visualization of FSx performance metrics

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for FSx, Lambda, CloudWatch, EventBridge, SNS, and S3

## Configuration

The application supports configuration through CDK context values. You can set these in `cdk.json` or pass them via command line:

### FSx Configuration
- `fsxStorageCapacity`: Storage capacity in GiB (default: 64)
- `fsxThroughputCapacity`: Throughput capacity in MBps (default: 64) 
- `fsxCacheSize`: SSD read cache size in GiB (default: 128)

### Monitoring Thresholds
- `cacheHitRatioThreshold`: Cache hit ratio alarm threshold (default: 70%)
- `storageUtilizationThreshold`: Storage utilization alarm threshold (default: 85%)
- `networkUtilizationThreshold`: Network utilization alarm threshold (default: 90%)

### Automation Schedules
- `lifecyclePolicySchedule`: Schedule for policy analysis (default: "rate(1 hour)")
- `costReportingSchedule`: Schedule for cost reporting (default: "rate(24 hours)")

### Notifications
- `notificationEmail`: Email address for SNS notifications (optional)

### Tagging
- `environment`: Environment name (default: "development")
- `owner`: Owner/team name (default: "devops")
- `costCenter`: Cost center for billing (default: "infrastructure")

## Deployment

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Build the application:**
   ```bash
   npm run build
   ```

3. **Synthesize CloudFormation template (optional):**
   ```bash
   cdk synth
   ```

4. **Deploy the stack:**
   ```bash
   cdk deploy
   ```

   Or deploy with custom configuration:
   ```bash
   cdk deploy \
     --context fsxStorageCapacity=128 \
     --context fsxThroughputCapacity=128 \
     --context fsxCacheSize=256 \
     --context notificationEmail=admin@company.com \
     --context environment=production
   ```

5. **Verify deployment:**
   After deployment, check the CloudFormation outputs for resource information including FSx file system ID, Lambda function ARNs, and dashboard URL.

## Usage

### Mounting the File System

After deployment, mount the FSx file system using the DNS name from the stack outputs:

```bash
# Replace with your actual DNS name from stack outputs
FSX_DNS_NAME="fs-0123456789abcdef0.fsx.us-west-2.amazonaws.com"

# Create mount point
sudo mkdir /mnt/fsx

# Mount the file system (NFS v4.1)
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  ${FSX_DNS_NAME}:/ /mnt/fsx
```

### Monitoring

The solution provides several monitoring capabilities:

1. **CloudWatch Dashboard**: View real-time FSx performance metrics
2. **CloudWatch Alarms**: Receive alerts for performance issues
3. **Cost Reports**: Automated S3 reports with optimization recommendations
4. **SNS Notifications**: Real-time alerts and policy recommendations

### Cost Optimization

The Lambda functions automatically:

- Analyze cache hit ratios and storage utilization patterns
- Generate cost optimization recommendations
- Provide intelligent alerts for performance issues
- Create detailed usage reports stored in S3

## Customization

### Adjusting Monitoring Thresholds

Modify thresholds in `cdk.json` or during deployment:

```bash
cdk deploy \
  --context cacheHitRatioThreshold=80 \
  --context storageUtilizationThreshold=90 \
  --context networkUtilizationThreshold=95
```

### Changing Automation Schedules

Update schedules using cron or rate expressions:

```bash
cdk deploy \
  --context lifecyclePolicySchedule="cron(0 */6 * * ? *)" \
  --context costReportingSchedule="cron(0 6 * * ? *)"
```

### Adding Email Notifications

Configure email notifications:

```bash
cdk deploy --context notificationEmail=your-email@company.com
```

## Development

### Local Development

1. **Watch for changes:**
   ```bash
   npm run watch
   ```

2. **Run tests:**
   ```bash
   npm test
   ```

3. **Lint code:**
   ```bash
   npm run lint
   ```

### Adding Features

To extend the solution:

1. Modify `lib/automated-file-lifecycle-management-stack.ts`
2. Add new Lambda function code inline or as separate files
3. Update monitoring thresholds and alarms as needed
4. Test changes with `cdk diff` before deployment

## Cleanup

To remove all resources:

```bash
cdk destroy
```

This will delete all AWS resources created by the stack, including:
- FSx file system and data
- Lambda functions
- CloudWatch alarms and dashboard
- S3 bucket and reports
- SNS topic and subscriptions

## Troubleshooting

### Common Issues

1. **FSx Creation Fails**: Ensure you have appropriate VPC and subnet configuration
2. **Lambda Timeouts**: Check CloudWatch logs for function execution details
3. **Permission Errors**: Verify IAM roles have necessary permissions
4. **Missing Metrics**: FSx metrics may take time to appear in CloudWatch

### Debugging

- Check CloudWatch logs for Lambda function execution details
- Review CloudFormation events for deployment issues
- Use `cdk diff` to see what changes will be made
- Enable debug logging with `--debug` flag

### Support

For issues with:
- **CDK**: Check AWS CDK documentation and GitHub issues
- **FSx**: Review AWS FSx documentation and service limits
- **Lambda**: Check function logs in CloudWatch

## Cost Considerations

This solution includes several cost optimization features:

- **FSx Intelligent Tiering**: Automatically moves data between storage tiers
- **Cost Reporting**: Regular analysis of storage utilization and recommendations
- **Right-sizing Alerts**: Notifications for over/under-provisioned resources
- **Lifecycle Management**: Automated policies to optimize storage costs

Monitor your AWS bill regularly and adjust capacity based on the cost reports and recommendations provided by the system.

## Security Best Practices

The solution implements several security best practices:

- **Least Privilege IAM**: Lambda functions have minimal required permissions
- **Encrypted Storage**: S3 bucket uses server-side encryption
- **VPC Security**: FSx deployed with appropriate security groups
- **SNS Encryption**: Topic uses server-side encryption
- **Secure Communication**: All AWS service communication uses SSL/TLS

## Performance Optimization

To optimize performance:

1. **Monitor Cache Hit Ratio**: Maintain >80% for optimal performance
2. **Right-size Throughput**: Adjust based on actual usage patterns  
3. **Client Optimization**: Use appropriate NFS mount options
4. **Network Configuration**: Ensure adequate network bandwidth

The automated system will provide recommendations for performance improvements based on real usage data.