# Data Expiration Automation with DynamoDB TTL - CDK TypeScript

This CDK TypeScript application implements the complete infrastructure for the "Data Expiration Automation with DynamoDB TTL" recipe. The solution creates a DynamoDB table with Time-To-Live (TTL) feature enabled for automated data lifecycle management.

## Architecture

The CDK application deploys:

- **DynamoDB Table**: Session data table with TTL enabled on the `expires_at` attribute
- **CloudWatch Dashboard**: Monitoring dashboard for TTL deletion metrics and table statistics
- **CloudWatch Alarms**: Alerts for unusual TTL deletion patterns
- **IAM Outputs**: Table name, ARN, and configuration details for application integration

## Prerequisites

- Node.js 18+ installed
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- IAM permissions for DynamoDB, CloudWatch, and CDK operations

## Required AWS Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:UpdateTimeToLive",
        "dynamodb:DescribeTimeToLive",
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "cloudwatch:PutDashboard",
        "cloudwatch:DeleteDashboard",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not done previously)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template (optional, for validation)
cdk synth

# Deploy the infrastructure
cdk deploy
```

### 4. Verify Deployment

After deployment, the output will display:
- DynamoDB table name and ARN
- CloudWatch dashboard URL
- Sample CLI commands for testing

## Testing the TTL Feature

### Insert Items with TTL Values

```bash
# Set your table name from the CDK output
TABLE_NAME="session-data-abc123"  # Replace with actual table name

# Calculate Unix timestamps for different expiration times
CURRENT_TIME=$(date +%s)
SHORT_TTL=$((CURRENT_TIME + 300))    # Expires in 5 minutes
LONG_TTL=$((CURRENT_TIME + 1800))    # Expires in 30 minutes

# Insert active session (long TTL)
aws dynamodb put-item \
    --table-name ${TABLE_NAME} \
    --item '{
        "user_id": {"S": "user123"},
        "session_id": {"S": "session_active"},
        "login_time": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"},
        "last_activity": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"},
        "expires_at": {"N": "'${LONG_TTL}'"}
    }'

# Insert temporary session (short TTL)
aws dynamodb put-item \
    --table-name ${TABLE_NAME} \
    --item '{
        "user_id": {"S": "user456"},
        "session_id": {"S": "session_temp"},
        "login_time": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"},
        "session_type": {"S": "temporary"},
        "expires_at": {"N": "'${SHORT_TTL}'"}
    }'
```

### Query Active Items Only

```bash
# Scan for non-expired items using filter expression
CURRENT_EPOCH=$(date +%s)

aws dynamodb scan \
    --table-name ${TABLE_NAME} \
    --filter-expression "#ttl > :current_time" \
    --expression-attribute-names '{"#ttl": "expires_at"}' \
    --expression-attribute-values '{":current_time": {"N": "'${CURRENT_EPOCH}'"}}' \
    --output table
```

### Monitor TTL Deletions

```bash
# Check TTL configuration
aws dynamodb describe-time-to-live --table-name ${TABLE_NAME}

# View CloudWatch metrics for TTL deletions
aws cloudwatch get-metric-statistics \
    --namespace "AWS/DynamoDB" \
    --metric-name "TimeToLiveDeletedItemCount" \
    --dimensions Name=TableName,Value=${TABLE_NAME} \
    --start-time $(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ") \
    --end-time $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
    --period 300 \
    --statistics Sum
```

## Monitoring and Observability

### CloudWatch Dashboard

The deployed dashboard includes widgets for:
- TTL deletion count over time
- Table item count and size metrics
- Read/write capacity unit consumption

Access the dashboard through the AWS Console using the URL provided in the CDK output.

### CloudWatch Alarms

The stack creates an alarm that triggers when TTL deletions exceed the configured threshold (default: 1000 deletions per 5-minute period). Adjust the threshold in `app.ts` based on your expected deletion volume.

## Application Integration

### Environment Variables

After deployment, set these environment variables in your application:

```bash
export DYNAMODB_TABLE_NAME="your-table-name"  # From CDK output
export TTL_ATTRIBUTE="expires_at"
export AWS_REGION="your-aws-region"
```

### Sample Application Code

#### Node.js/TypeScript Example

```typescript
import { DynamoDBClient, PutItemCommand, ScanCommand } from "@aws-sdk/client-dynamodb";

const client = new DynamoDBClient({ region: process.env.AWS_REGION });
const tableName = process.env.DYNAMODB_TABLE_NAME;

// Create session with TTL
async function createSession(userId: string, sessionId: string, ttlSeconds: number) {
  const expiresAt = Math.floor(Date.now() / 1000) + ttlSeconds;
  
  const command = new PutItemCommand({
    TableName: tableName,
    Item: {
      user_id: { S: userId },
      session_id: { S: sessionId },
      created_at: { S: new Date().toISOString() },
      expires_at: { N: expiresAt.toString() }
    }
  });
  
  return await client.send(command);
}

// Get active sessions only
async function getActiveSessions() {
  const currentTime = Math.floor(Date.now() / 1000);
  
  const command = new ScanCommand({
    TableName: tableName,
    FilterExpression: "#ttl > :current_time",
    ExpressionAttributeNames: {
      "#ttl": "expires_at"
    },
    ExpressionAttributeValues: {
      ":current_time": { N: currentTime.toString() }
    }
  });
  
  return await client.send(command);
}
```

#### Python Example

```python
import boto3
import time
from datetime import datetime

dynamodb = boto3.client('dynamodb')
table_name = os.environ['DYNAMODB_TABLE_NAME']

def create_session(user_id: str, session_id: str, ttl_seconds: int):
    expires_at = int(time.time()) + ttl_seconds
    
    return dynamodb.put_item(
        TableName=table_name,
        Item={
            'user_id': {'S': user_id},
            'session_id': {'S': session_id},
            'created_at': {'S': datetime.utcnow().isoformat()},
            'expires_at': {'N': str(expires_at)}
        }
    )

def get_active_sessions():
    current_time = int(time.time())
    
    return dynamodb.scan(
        TableName=table_name,
        FilterExpression='#ttl > :current_time',
        ExpressionAttributeNames={'#ttl': 'expires_at'},
        ExpressionAttributeValues={':current_time': {'N': str(current_time)}}
    )
```

## Cost Optimization

### TTL Benefits
- **No Write Capacity Consumption**: TTL deletions don't consume write capacity units
- **Automatic Cleanup**: Eliminates need for manual data lifecycle management
- **Storage Cost Reduction**: Automatically removes expired data to reduce storage costs
- **Performance Improvement**: Smaller dataset sizes improve query performance

### Cost Estimation
- **DynamoDB On-Demand**: Pay per request with no minimum fees
- **Storage**: $0.25 per GB-month for data storage
- **CloudWatch**: Dashboard and alarm costs are minimal for monitoring
- **Estimated Monthly Cost**: $0.25-$2.00 for typical session data workloads

## Security Best Practices

### IAM Permissions
The CDK stack follows least privilege principles:
- Table access is controlled through IAM policies
- CloudWatch metrics are read-only
- No overly permissive wildcard permissions

### Data Protection
- Point-in-time recovery is enabled for data protection
- TTL ensures automatic cleanup of sensitive session data
- Consider encryption at rest for sensitive workloads

### Network Security
- Deploy in private subnets if accessing from VPC
- Use VPC endpoints for DynamoDB access from private networks
- Implement proper security groups and NACLs

## Troubleshooting

### Common Issues

1. **TTL Not Working**: TTL deletions can take up to 48 hours to occur
2. **Permission Errors**: Ensure IAM permissions include all required DynamoDB actions
3. **High Costs**: Monitor read/write capacity consumption and optimize query patterns

### Debug Commands

```bash
# Check TTL configuration
aws dynamodb describe-time-to-live --table-name ${TABLE_NAME}

# View table details
aws dynamodb describe-table --table-name ${TABLE_NAME}

# Check CloudWatch logs for CDK deployment issues
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/CDK
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

This will delete:
- DynamoDB table and all data
- CloudWatch dashboard and alarms
- All associated resources created by the stack

## Development

### Project Structure

```
├── app.ts              # Main CDK application
├── package.json        # Node.js dependencies and scripts
├── tsconfig.json       # TypeScript configuration
├── cdk.json           # CDK configuration
└── README.md          # This documentation
```

### Available Scripts

```bash
npm run build          # Compile TypeScript
npm run watch          # Watch mode for development
npm run test           # Run tests (if implemented)
npm run synth          # Synthesize CloudFormation template
npm run deploy         # Deploy to AWS
npm run destroy        # Remove all resources
```

## Additional Resources

- [DynamoDB TTL Documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html)
- [AWS CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws-dynamodb-readme.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [CloudWatch DynamoDB Metrics](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/monitoring-cloudwatch.html)

## Support

For issues with this CDK application:
1. Check the troubleshooting section above
2. Review AWS CloudFormation stack events in the AWS Console
3. Consult the original recipe documentation
4. Refer to AWS CDK and DynamoDB documentation