# Multi-Agent AI Workflows with Amazon Bedrock AgentCore - CDK Python

This CDK Python application deploys a complete multi-agent AI system using Amazon Bedrock agents, AWS Lambda for orchestration, Amazon EventBridge for event-driven coordination, and DynamoDB for shared memory management.

## Architecture

The application creates:

- **Amazon Bedrock Agents**: Supervisor and specialized agents (Finance, Support, Analytics)
- **AWS Lambda Function**: Central coordinator for workflow orchestration
- **Amazon EventBridge**: Custom event bus for agent communication
- **Amazon DynamoDB**: Shared memory table for agent context
- **Amazon SQS**: Dead letter queue for failed events
- **CloudWatch**: Comprehensive monitoring and logging
- **IAM Roles**: Least-privilege security policies

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.8 or later
- Node.js 14.x or later (for CDK CLI)
- AWS CDK v2 CLI installed (`npm install -g aws-cdk`)
- AWS account with Amazon Bedrock model access enabled

## Installation

1. **Clone and navigate to the CDK Python directory:**
   ```bash
   cd aws/multi-agent-ai-workflows-bedrock-agentcore/code/cdk-python/
   ```

2. **Create and activate a virtual environment:**
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install Python dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Install development dependencies (optional):**
   ```bash
   pip install -e ".[dev]"
   ```

## Deployment

1. **Bootstrap CDK in your account (first time only):**
   ```bash
   cdk bootstrap
   ```

2. **Synthesize the CloudFormation template:**
   ```bash
   cdk synth
   ```

3. **Deploy the stack:**
   ```bash
   cdk deploy
   ```

   The deployment will create all necessary resources and output important identifiers:
   - Agent Memory Table Name
   - EventBridge Bus Name
   - Coordinator Function Name
   - Supervisor Agent ID
   - Dead Letter Queue URL

## Configuration

### Environment Variables

Set these environment variables to customize the deployment:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1  # or your preferred region
```

### Context Parameters

You can also set configuration in `cdk.json` or via CLI:

```bash
cdk deploy -c account=123456789012 -c region=us-west-2
```

## Usage

### Testing the Multi-Agent System

1. **Send a test event to EventBridge:**
   ```bash
   aws events put-events \
     --entries '[{
       "Source": "multi-agent.system",
       "DetailType": "Agent Task Request",
       "Detail": "{\"taskType\":\"financial_analysis\",\"requestData\":\"Q4 revenue analysis\",\"correlationId\":\"test-123\",\"sessionId\":\"session-456\"}",
       "EventBusName": "multi-agent-bus-multiagentworkflowstack"
     }]'
   ```

2. **Check Lambda logs:**
   ```bash
   aws logs tail /aws/lambda/agent-coordinator-multiagentworkflowstack --since 5m
   ```

3. **Query agent memory:**
   ```bash
   aws dynamodb scan \
     --table-name agent-memory-multiagentworkflowstack \
     --limit 5
   ```

### Invoking Bedrock Agents Directly

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <supervisor-agent-id> \
  --agent-alias-id <alias-id> \
  --session-id test-session-$(date +%s) \
  --input-text "Coordinate a business analysis including financial review, customer satisfaction analysis, and sales trends."
```

## Monitoring

### CloudWatch Dashboards

The application creates log groups for monitoring:
- `/aws/bedrock/agents/multi-agent-workflow`
- `/aws/lambda/agent-coordinator-*`

### Key Metrics to Monitor

- **Lambda Duration**: Coordination function execution time
- **EventBridge Matched Events**: Event routing success rate
- **DynamoDB Metrics**: Memory table read/write capacity
- **Bedrock Agent Invocations**: Agent usage and latency
- **Dead Letter Queue Messages**: Failed event processing

### X-Ray Tracing

The Lambda coordinator has X-Ray tracing enabled for distributed request tracking across the multi-agent system.

## Security

The application implements security best practices:

### IAM Policies

- **Lambda Role**: Minimum permissions for DynamoDB, EventBridge, and Bedrock
- **Bedrock Agent Role**: Scoped access to required services
- **Resource-based Policies**: Restrict access to specific resources

### Data Protection

- **DynamoDB Encryption**: Server-side encryption at rest
- **Lambda Environment Variables**: Secure configuration management
- **EventBridge**: Encrypted event payloads

### Network Security

- **VPC Integration**: Optional VPC deployment for network isolation
- **Security Groups**: Restricted network access (if using VPC)

## Cost Optimization

### Pay-per-Request Resources

- **DynamoDB**: Automatic scaling based on demand
- **Lambda**: Charged only for execution time
- **EventBridge**: Pay per event processed

### Resource Cleanup

- **TTL on DynamoDB**: Automatic cleanup of old agent memory
- **Log Retention**: 30-day retention for cost control

## Troubleshooting

### Common Issues

1. **Bedrock Model Access**
   ```bash
   # Request model access in AWS Console > Bedrock > Model Access
   aws bedrock list-foundation-models --region us-east-1
   ```

2. **IAM Permissions**
   ```bash
   # Verify CDK deployment role has necessary permissions
   aws iam get-role --role-name cdk-*-cfn-exec-role-*
   ```

3. **Agent Creation Failures**
   ```bash
   # Check CloudFormation events
   aws cloudformation describe-stack-events --stack-name MultiAgentWorkflowStack
   ```

### Debugging

Enable debug logging:
```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

## Development

### Code Structure

```
cdk-python/
├── app.py                          # CDK application entry point
├── cdk.json                        # CDK configuration
├── requirements.txt                # Python dependencies
├── setup.py                        # Package configuration
├── multi_agent_workflow/
│   ├── __init__.py
│   └── multi_agent_workflow_stack.py  # Main stack definition
└── README.md                       # This file
```

### Testing

Run unit tests:
```bash
python -m pytest tests/ -v
```

Run type checking:
```bash
mypy multi_agent_workflow/
```

Format code:
```bash
black multi_agent_workflow/
flake8 multi_agent_workflow/
```

### Custom Agent Instructions

Modify agent instructions in `multi_agent_workflow_stack.py`:

```python
agent_configs = [
    {
        "name": "custom_agent",
        "description": "Custom specialized agent",
        "instruction": "Your custom instructions here...",
        "session_ttl": 1800
    }
]
```

## Cleanup

Remove all resources:
```bash
cdk destroy
```

Confirm deletion when prompted. This will remove:
- All Bedrock agents and aliases
- Lambda function and IAM roles
- DynamoDB table and data
- EventBridge rules and custom bus
- CloudWatch log groups
- SQS dead letter queue

## Support

For issues with this CDK application:

1. Check the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
2. Review [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/)
3. Consult the original recipe documentation
4. Check AWS CloudFormation events for deployment issues

## License

This sample code is provided under the MIT License. See the LICENSE file for details.