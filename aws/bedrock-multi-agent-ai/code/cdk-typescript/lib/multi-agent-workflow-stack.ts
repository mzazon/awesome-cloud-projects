import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as bedrock from 'aws-cdk-lib/aws-bedrock';
import { Construct } from 'constructs';

export interface MultiAgentWorkflowStackProps extends cdk.StackProps {
  uniqueSuffix: string;
}

export class MultiAgentWorkflowStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: MultiAgentWorkflowStackProps) {
    super(scope, id, props);

    const { uniqueSuffix } = props;

    // Create IAM role for Bedrock agents
    const bedrockAgentRole = new iam.Role(this, 'BedrockAgentRole', {
      roleName: `BedrockAgentRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('bedrock.amazonaws.com'),
      description: 'IAM role for Bedrock agents in multi-agent workflow',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonBedrockFullAccess'),
      ],
    });

    // Create DynamoDB table for agent memory management
    const memoryTable = new dynamodb.Table(this, 'AgentMemoryTable', {
      tableName: `agent-memory-${uniqueSuffix}`,
      partitionKey: { name: 'SessionId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'Timestamp', type: dynamodb.AttributeType.NUMBER },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      tags: [
        {
          key: 'Project',
          value: 'MultiAgentWorkflow',
        },
      ],
    });

    // Create custom EventBridge bus for agent communication
    const eventBus = new events.EventBus(this, 'MultiAgentEventBus', {
      eventBusName: `multi-agent-bus-${uniqueSuffix}`,
      description: 'Event bus for multi-agent workflow coordination',
    });

    // Create SQS Dead Letter Queue for failed events
    const deadLetterQueue = new sqs.Queue(this, 'MultiAgentDLQ', {
      queueName: `multi-agent-dlq-${uniqueSuffix}`,
      retentionPeriod: cdk.Duration.days(14),
      visibilityTimeout: cdk.Duration.seconds(60),
    });

    // Create IAM role for Lambda coordinator function
    const lambdaRole = new iam.Role(this, 'LambdaCoordinatorRole', {
      roleName: `LambdaCoordinatorRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda coordinator function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEventBridgeFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonBedrockFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonDynamoDBFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
    });

    // Create Lambda function for workflow coordination
    const coordinatorFunction = new lambda.Function(this, 'AgentCoordinator', {
      functionName: `agent-coordinator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'coordinator.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

eventbridge = boto3.client('events')
bedrock_agent = boto3.client('bedrock-agent-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Coordinate multi-agent workflows based on EventBridge events"""
    
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        task_type = detail.get('taskType')
        request_data = detail.get('requestData')
        correlation_id = detail.get('correlationId')
        session_id = detail.get('sessionId', correlation_id)
        
        logger.info(f"Processing task: {task_type} with correlation: {correlation_id}")
        
        # Store task in memory table
        memory_table = dynamodb.Table('${memoryTable.tableName}')
        
        memory_table.put_item(
            Item={
                'SessionId': session_id,
                'Timestamp': int(datetime.now().timestamp()),
                'TaskType': task_type,
                'RequestData': request_data,
                'Status': 'processing'
            }
        )
        
        # Route to appropriate agent based on task type
        agent_response = route_to_agent(task_type, request_data, session_id)
        
        # Update memory with result
        memory_table.put_item(
            Item={
                'SessionId': session_id,
                'Timestamp': int(datetime.now().timestamp()),
                'TaskType': task_type,
                'Response': agent_response,
                'Status': 'completed'
            }
        )
        
        # Publish completion event
        eventbridge.put_events(
            Entries=[{
                'Source': 'multi-agent.coordinator',
                'DetailType': 'Agent Task Completed',
                'Detail': json.dumps({
                    'correlationId': correlation_id,
                    'taskType': task_type,
                    'result': agent_response,
                    'status': 'completed'
                }),
                'EventBusName': '${eventBus.eventBusName}'
            }]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Task coordinated successfully',
                'correlationId': correlation_id
            })
        }
        
    except Exception as e:
        logger.error(f"Coordination error: {str(e)}")
        
        # Publish error event
        eventbridge.put_events(
            Entries=[{
                'Source': 'multi-agent.coordinator',
                'DetailType': 'Agent Task Failed',
                'Detail': json.dumps({
                    'correlationId': correlation_id,
                    'error': str(e),
                    'status': 'failed'
                }),
                'EventBusName': '${eventBus.eventBusName}'
            }]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def route_to_agent(task_type, request_data, session_id):
    """Route task to appropriate specialized agent"""
    
    # This is a simplified routing function
    # In production, this would invoke actual Bedrock agents
    agent_responses = {
        'financial_analysis': f"Financial analysis completed for: {request_data}",
        'customer_support': f"Customer support response for: {request_data}",
        'data_analytics': f"Analytics insights for: {request_data}"
    }
    
    return agent_responses.get(task_type, f"Processed by general agent: {request_data}")
`),
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        EVENT_BUS_NAME: eventBus.eventBusName,
        MEMORY_TABLE_NAME: memoryTable.tableName,
      },
      tracing: lambda.Tracing.ACTIVE,
      deadLetterQueue: deadLetterQueue,
      description: 'Lambda function for coordinating multi-agent workflows',
    });

    // Create EventBridge rule for agent task routing
    const taskRoutingRule = new events.Rule(this, 'AgentTaskRouter', {
      ruleName: 'agent-task-router',
      eventBus: eventBus,
      description: 'Routes tasks to specialized agents',
      eventPattern: {
        source: ['multi-agent.system'],
        detailType: ['Agent Task Request'],
      },
    });

    // Add Lambda target to EventBridge rule
    taskRoutingRule.addTarget(
      new targets.LambdaFunction(coordinatorFunction, {
        deadLetterQueue: deadLetterQueue,
        retryAttempts: 3,
      })
    );

    // Create CloudWatch Log Groups for agents
    const supervisorLogGroup = new logs.LogGroup(this, 'SupervisorAgentLogGroup', {
      logGroupName: '/aws/bedrock/agents/supervisor',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const specializedLogGroup = new logs.LogGroup(this, 'SpecializedAgentLogGroup', {
      logGroupName: '/aws/bedrock/agents/specialized',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const lambdaLogGroup = new logs.LogGroup(this, 'LambdaCoordinatorLogGroup', {
      logGroupName: `/aws/lambda/${coordinatorFunction.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Bedrock Agents (Note: CDK L2 constructs for Bedrock agents are limited,
    // these would typically be created via L1 constructs or custom resources)
    
    // Supervisor Agent
    const supervisorAgent = new bedrock.CfnAgent(this, 'SupervisorAgent', {
      agentName: `supervisor-agent-${uniqueSuffix}`,
      agentResourceRoleArn: bedrockAgentRole.roleArn,
      description: 'Supervisor agent for multi-agent workflow coordination',
      foundationModel: 'anthropic.claude-3-sonnet-20240229-v1:0',
      instruction: `You are a supervisor agent responsible for coordinating complex business tasks across specialized agent teams. Your responsibilities include:
1. Analyzing incoming requests and breaking them into sub-tasks
2. Routing tasks to appropriate specialist agents: Financial Agent for financial analysis, Support Agent for customer service, Analytics Agent for data analysis
3. Coordinating parallel work streams and managing dependencies
4. Synthesizing results from multiple agents into cohesive responses
5. Ensuring quality control and consistency across agent outputs
Always provide clear task delegation and maintain oversight of the overall workflow progress.`,
      idleSessionTtlInSeconds: 3600,
    });

    // Financial Analysis Agent
    const financeAgent = new bedrock.CfnAgent(this, 'FinanceAgent', {
      agentName: `finance-agent-${uniqueSuffix}`,
      agentResourceRoleArn: bedrockAgentRole.roleArn,
      description: 'Specialized agent for financial analysis and reporting',
      foundationModel: 'anthropic.claude-3-sonnet-20240229-v1:0',
      instruction: `You are a financial analysis specialist. Your role is to analyze financial data, create reports, calculate metrics, and provide insights on financial performance. Always provide detailed explanations of your analysis methodology and cite relevant financial principles. Focus on accuracy and compliance with financial reporting standards.`,
      idleSessionTtlInSeconds: 1800,
    });

    // Customer Support Agent
    const supportAgent = new bedrock.CfnAgent(this, 'SupportAgent', {
      agentName: `support-agent-${uniqueSuffix}`,
      agentResourceRoleArn: bedrockAgentRole.roleArn,
      description: 'Specialized agent for customer support and service',
      foundationModel: 'anthropic.claude-3-sonnet-20240229-v1:0',
      instruction: `You are a customer support specialist. Your role is to help customers resolve issues, answer questions, and provide excellent service experiences. Always maintain a helpful, empathetic tone and focus on resolving customer concerns efficiently. Escalate complex technical issues when appropriate and always follow company policies.`,
      idleSessionTtlInSeconds: 1800,
    });

    // Analytics Agent
    const analyticsAgent = new bedrock.CfnAgent(this, 'AnalyticsAgent', {
      agentName: `analytics-agent-${uniqueSuffix}`,
      agentResourceRoleArn: bedrockAgentRole.roleArn,
      description: 'Specialized agent for data analysis and insights',
      foundationModel: 'anthropic.claude-3-sonnet-20240229-v1:0',
      instruction: `You are a data analytics specialist. Your role is to analyze datasets, identify patterns, create visualizations, and provide actionable insights. Focus on statistical accuracy, clear data interpretation, and practical business recommendations. Always explain your analytical methodology and validate your findings.`,
      idleSessionTtlInSeconds: 1800,
    });

    // Create CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'MultiAgentDashboard', {
      dashboardName: `MultiAgentWorkflow-${uniqueSuffix}`,
      start: '-PT6H',
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Performance',
        left: [
          coordinatorFunction.metricDuration(),
          coordinatorFunction.metricInvocations(),
          coordinatorFunction.metricErrors(),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'DynamoDB Performance',
        left: [
          memoryTable.metricConsumedReadCapacityUnits(),
          memoryTable.metricConsumedWriteCapacityUnits(),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'EventBridge Events',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Events',
            metricName: 'MatchedEvents',
            dimensionsMap: {
              EventBusName: eventBus.eventBusName,
            },
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'SupervisorAgentId', {
      value: supervisorAgent.attrAgentId,
      description: 'ID of the supervisor agent',
      exportName: `SupervisorAgentId-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'FinanceAgentId', {
      value: financeAgent.attrAgentId,
      description: 'ID of the finance agent',
      exportName: `FinanceAgentId-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'SupportAgentId', {
      value: supportAgent.attrAgentId,
      description: 'ID of the support agent',
      exportName: `SupportAgentId-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'AnalyticsAgentId', {
      value: analyticsAgent.attrAgentId,
      description: 'ID of the analytics agent',
      exportName: `AnalyticsAgentId-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'EventBusArn', {
      value: eventBus.eventBusArn,
      description: 'ARN of the multi-agent event bus',
      exportName: `EventBusArn-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'MemoryTableName', {
      value: memoryTable.tableName,
      description: 'Name of the agent memory DynamoDB table',
      exportName: `MemoryTableName-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'CoordinatorFunctionArn', {
      value: coordinatorFunction.functionArn,
      description: 'ARN of the coordinator Lambda function',
      exportName: `CoordinatorFunctionArn-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL of the CloudWatch dashboard',
      exportName: `DashboardUrl-${uniqueSuffix}`,
    });
  }
}