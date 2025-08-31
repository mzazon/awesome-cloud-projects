#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as bedrock from 'aws-cdk-lib/aws-bedrock';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Interactive Business Process Automation with Bedrock AgentCore and EventBridge
 * 
 * This stack creates:
 * - S3 bucket for document storage with versioning and encryption
 * - EventBridge custom event bus for intelligent event routing
 * - Lambda functions for business process handlers (approval, processing, notification)
 * - Lambda function for Bedrock Agent action group
 * - Bedrock Agent with action groups for document analysis
 * - IAM roles and policies with least privilege access
 * 
 * Architecture: AI-powered document processing with event-driven business workflows
 */
export class BusinessProcessAutomationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const projectName = `biz-automation-${randomSuffix}`;

    // ========================================
    // S3 Bucket for Document Storage
    // ========================================
    
    const documentBucket = new s3.Bucket(this, 'DocumentBucket', {
      bucketName: `${projectName}-documents`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
          expiredObjectDeleteMarker: true,
        },
      ],
    });

    // Add tags for cost allocation
    cdk.Tags.of(documentBucket).add('Project', projectName);
    cdk.Tags.of(documentBucket).add('Component', 'DocumentStorage');

    // ========================================
    // EventBridge Custom Event Bus
    // ========================================
    
    const customEventBus = new events.EventBus(this, 'CustomEventBus', {
      eventBusName: `${projectName}-events`,
      description: 'Custom event bus for business process automation events',
    });

    cdk.Tags.of(customEventBus).add('Project', projectName);
    cdk.Tags.of(customEventBus).add('Component', 'EventOrchestration');

    // ========================================
    // Lambda Execution Role
    // ========================================
    
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${projectName}-lambda-execution-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for business process Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        EventBridgeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['events:PutEvents'],
              resources: [customEventBus.eventBusArn],
            }),
          ],
        }),
      },
    });

    // ========================================
    // Lambda Functions for Business Processes
    // ========================================
    
    // Approval Process Lambda
    const approvalHandler = new lambda.Function(this, 'ApprovalHandler', {
      functionName: `${projectName}-approval`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Handles document approval workflows based on AI recommendations',
      logRetention: logs.RetentionDays.ONE_WEEK,
      environment: {
        PROJECT_NAME: projectName,
        EVENT_BUS_NAME: customEventBus.eventBusName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing approval event: {json.dumps(event)}")
    
    # Extract document details from EventBridge event
    detail = event['detail']
    document_name = detail['document_name']
    confidence_score = detail['confidence_score']
    recommendation = detail['recommendation']
    
    # Simulate approval logic based on AI recommendation
    if confidence_score > 0.85 and recommendation == 'APPROVE':
        status = 'AUTO_APPROVED'
        action = 'Document automatically approved'
    else:
        status = 'PENDING_REVIEW'
        action = 'Document requires human review'
    
    # Log the decision
    result = {
        'process_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'status': status,
        'action': action,
        'confidence_score': confidence_score
    }
    
    print(f"Approval result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
      `),
    });

    // Processing Lambda
    const processingHandler = new lambda.Function(this, 'ProcessingHandler', {
      functionName: `${projectName}-processing`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Handles automated document processing workflows',
      logRetention: logs.RetentionDays.ONE_WEEK,
      environment: {
        PROJECT_NAME: projectName,
        EVENT_BUS_NAME: customEventBus.eventBusName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing automation event: {json.dumps(event)}")
    
    detail = event['detail']
    document_name = detail['document_name']
    document_type = detail['document_type']
    extracted_data = detail.get('extracted_data', {})
    
    # Simulate different processing based on document type
    processing_actions = {
        'invoice': 'Initiated payment processing workflow',
        'contract': 'Routed to legal team for final review',
        'compliance': 'Submitted to regulatory reporting system',
        'default': 'Archived for future reference'
    }
    
    action = processing_actions.get(document_type, processing_actions['default'])
    
    result = {
        'process_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'document_type': document_type,
        'action': action,
        'data_extracted': len(extracted_data) > 0
    }
    
    print(f"Processing result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
      `),
    });

    // Notification Lambda
    const notificationHandler = new lambda.Function(this, 'NotificationHandler', {
      functionName: `${projectName}-notification`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Handles business process notifications and alerts',
      logRetention: logs.RetentionDays.ONE_WEEK,
      environment: {
        PROJECT_NAME: projectName,
        EVENT_BUS_NAME: customEventBus.eventBusName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing notification event: {json.dumps(event)}")
    
    detail = event['detail']
    document_name = detail['document_name']
    alert_type = detail['alert_type']
    message = detail['message']
    
    # Simulate notification routing
    notification_channels = {
        'high_priority': ['email', 'slack', 'sms'],
        'medium_priority': ['email', 'slack'],
        'low_priority': ['email']
    }
    
    channels = notification_channels.get(alert_type, ['email'])
    
    result = {
        'notification_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'alert_type': alert_type,
        'message': message,
        'channels': channels,
        'status': 'sent'
    }
    
    print(f"Notification result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
      `),
    });

    // ========================================
    // Agent Action Lambda Function
    // ========================================
    
    const agentActionHandler = new lambda.Function(this, 'AgentActionHandler', {
      functionName: `${projectName}-agent-action`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      description: 'Handles Bedrock Agent action group requests and publishes events',
      logRetention: logs.RetentionDays.ONE_WEEK,
      environment: {
        PROJECT_NAME: projectName,
        EVENT_BUS_NAME: customEventBus.eventBusName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import re
from datetime import datetime

s3_client = boto3.client('s3')
events_client = boto3.client('events')

def lambda_handler(event, context):
    print(f"Agent action request: {json.dumps(event)}")
    
    # Parse agent request
    action_request = event['actionRequest']
    api_path = action_request['apiPath']
    parameters = action_request.get('parameters', [])
    
    # Extract parameters
    document_path = None
    document_type = None
    
    for param in parameters:
        if param['name'] == 'document_path':
            document_path = param['value']
        elif param['name'] == 'document_type':
            document_type = param['value']
    
    if api_path == '/analyze-document':
        result = analyze_document(document_path, document_type)
        
        # Publish event to EventBridge
        publish_event(result)
        
        return {
            'response': {
                'actionResponse': {
                    'responseBody': result
                }
            }
        }
    
    return {
        'response': {
            'actionResponse': {
                'responseBody': {'error': 'Unknown action'}
            }
        }
    }

def analyze_document(document_path, document_type):
    # Simulate document analysis
    analysis_results = {
        'invoice': {
            'recommendation': 'APPROVE',
            'confidence_score': 0.92,
            'extracted_data': {
                'amount': 1250.00,
                'vendor': 'TechSupplies Inc',
                'due_date': '2024-01-15'
            },
            'alert_type': 'medium_priority'
        },
        'contract': {
            'recommendation': 'REVIEW',
            'confidence_score': 0.75,
            'extracted_data': {
                'contract_value': 50000.00,
                'term_length': '12 months',
                'party': 'Global Services LLC'
            },
            'alert_type': 'high_priority'
        },
        'compliance': {
            'recommendation': 'APPROVE',
            'confidence_score': 0.88,
            'extracted_data': {
                'regulation': 'SOX',
                'compliance_score': 95,
                'review_date': '2024-01-01'
            },
            'alert_type': 'low_priority'
        }
    }
    
    return analysis_results.get(document_type, {
        'recommendation': 'REVIEW',
        'confidence_score': 0.5,
        'extracted_data': {},
        'alert_type': 'medium_priority'
    })

def publish_event(analysis_result):
    event_detail = {
        'document_name': 'sample-document.pdf',
        'document_type': 'invoice',
        'timestamp': datetime.utcnow().isoformat(),
        **analysis_result
    }
    
    events_client.put_events(
        Entries=[
            {
                'Source': 'bedrock.agent',
                'DetailType': 'Document Analysis Complete',
                'Detail': json.dumps(event_detail),
                'EventBusName': '${customEventBus.eventBusName}'
            }
        ]
    )
      `.replace('${customEventBus.eventBusName}', customEventBus.eventBusName)),
    });

    // Grant EventBridge publish permissions to agent action handler
    agentActionHandler.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['events:PutEvents'],
        resources: [customEventBus.eventBusArn],
      })
    );

    // ========================================
    // EventBridge Rules and Targets
    // ========================================
    
    // High-confidence approval rule
    const approvalRule = new events.Rule(this, 'ApprovalRule', {
      ruleName: `${projectName}-approval-rule`,
      eventBus: customEventBus,
      description: 'Route high-confidence approvals',
      eventPattern: {
        source: ['bedrock.agent'],
        detailType: ['Document Analysis Complete'],
        detail: {
          recommendation: ['APPROVE'],
          'confidence_score': [{ numeric: ['>=', 0.8] }],
        },
      },
    });

    approvalRule.addTarget(new targets.LambdaFunction(approvalHandler));

    // Document processing rule
    const processingRule = new events.Rule(this, 'ProcessingRule', {
      ruleName: `${projectName}-processing-rule`,
      eventBus: customEventBus,
      description: 'Route documents for automated processing',
      eventPattern: {
        source: ['bedrock.agent'],
        detailType: ['Document Analysis Complete'],
        detail: {
          'document_type': ['invoice', 'contract', 'compliance'],
        },
      },
    });

    processingRule.addTarget(new targets.LambdaFunction(processingHandler));

    // Alert and notification rule
    const alertRule = new events.Rule(this, 'AlertRule', {
      ruleName: `${projectName}-alert-rule`,
      eventBus: customEventBus,
      description: 'Route alerts and notifications',
      eventPattern: {
        source: ['bedrock.agent'],
        detailType: ['Document Analysis Complete'],
        detail: {
          'alert_type': ['high_priority', 'compliance_issue', 'error'],
        },
      },
    });

    alertRule.addTarget(new targets.LambdaFunction(notificationHandler));

    // ========================================
    // Bedrock Agent IAM Role
    // ========================================
    
    const agentRole = new iam.Role(this, 'BedrockAgentRole', {
      roleName: `${projectName}-agent-role`,
      assumedBy: new iam.ServicePrincipal('bedrock.amazonaws.com'),
      description: 'Role for Bedrock Agent business automation',
      inlinePolicies: {
        BedrockModelAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'bedrock:InvokeModel',
                'bedrock:Retrieve',
              ],
              resources: ['*'],
            }),
          ],
        }),
        S3DocumentAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:ListBucket',
              ],
              resources: [
                documentBucket.bucketArn,
                `${documentBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        EventBridgePublish: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['events:PutEvents'],
              resources: [customEventBus.eventBusArn],
            }),
          ],
        }),
        LambdaInvoke: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [agentActionHandler.functionArn],
            }),
          ],
        }),
      },
    });

    // ========================================
    // Bedrock Agent Configuration
    // ========================================
    
    // Note: CDK L2 constructs for Bedrock Agents are not yet available
    // Using L1 constructs (CfnAgent) for now
    const bedrockAgent = new bedrock.CfnAgent(this, 'BedrockAgent', {
      agentName: `${projectName}-agent`,
      agentResourceRoleArn: agentRole.roleArn,
      foundationModel: 'anthropic.claude-3-sonnet-20240229-v1:0',
      instruction: `You are a business process automation agent. Analyze documents uploaded to S3, extract key information, make recommendations for approval or processing, and trigger appropriate business workflows through EventBridge events. Focus on accuracy, compliance, and efficient processing.`,
      description: 'AI agent for intelligent business process automation',
      idleSessionTtlInSeconds: 1800,
      actionGroups: [
        {
          actionGroupName: 'DocumentProcessing',
          actionGroupExecutor: {
            lambda: agentActionHandler.functionArn,
          },
          apiSchema: {
            payload: JSON.stringify({
              openapi: '3.0.0',
              info: {
                title: 'Business Process Automation API',
                version: '1.0.0',
                description: 'API for AI agent business process automation',
              },
              paths: {
                '/analyze-document': {
                  post: {
                    description: 'Analyze business document and trigger appropriate workflows',
                    parameters: [
                      {
                        name: 'document_path',
                        in: 'query',
                        description: 'S3 path to the document',
                        required: true,
                        schema: { type: 'string' },
                      },
                      {
                        name: 'document_type',
                        in: 'query',
                        description: 'Type of document (invoice, contract, compliance)',
                        required: true,
                        schema: { type: 'string' },
                      },
                    ],
                    responses: {
                      '200': {
                        description: 'Document analysis completed',
                        content: {
                          'application/json': {
                            schema: {
                              type: 'object',
                              properties: {
                                recommendation: { type: 'string' },
                                confidence_score: { type: 'number' },
                                extracted_data: { type: 'object' },
                                next_actions: { type: 'array' },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            }),
          },
          description: 'Action group for business document processing and workflow automation',
        },
      ],
    });

    // Create agent alias after agent is created
    const agentAlias = new bedrock.CfnAgentAlias(this, 'BedrockAgentAlias', {
      agentId: bedrockAgent.attrAgentId,
      agentAliasName: 'production',
      description: 'Production alias for business automation agent',
    });

    // ========================================
    // Outputs
    // ========================================
    
    new cdk.CfnOutput(this, 'DocumentBucketName', {
      value: documentBucket.bucketName,
      description: 'S3 bucket for document storage',
      exportName: `${this.stackName}-DocumentBucket`,
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: customEventBus.eventBusName,
      description: 'Custom EventBridge event bus for business automation',
      exportName: `${this.stackName}-EventBus`,
    });

    new cdk.CfnOutput(this, 'BedrockAgentId', {
      value: bedrockAgent.attrAgentId,
      description: 'Bedrock Agent ID for business process automation',
      exportName: `${this.stackName}-AgentId`,
    });

    new cdk.CfnOutput(this, 'BedrockAgentAliasId', {
      value: agentAlias.attrAgentAliasId,
      description: 'Bedrock Agent Alias ID for production use',
      exportName: `${this.stackName}-AgentAliasId`,
    });

    new cdk.CfnOutput(this, 'ApprovalFunctionName', {
      value: approvalHandler.functionName,
      description: 'Lambda function for approval processing',
      exportName: `${this.stackName}-ApprovalFunction`,
    });

    new cdk.CfnOutput(this, 'ProcessingFunctionName', {
      value: processingHandler.functionName,
      description: 'Lambda function for document processing',
      exportName: `${this.stackName}-ProcessingFunction`,
    });

    new cdk.CfnOutput(this, 'NotificationFunctionName', {
      value: notificationHandler.functionName,
      description: 'Lambda function for notifications',
      exportName: `${this.stackName}-NotificationFunction`,
    });

    // Add comprehensive tags to all resources
    cdk.Tags.of(this).add('Project', projectName);
    cdk.Tags.of(this).add('Recipe', 'business-process-automation-agentcore-eventbridge');
    cdk.Tags.of(this).add('Environment', 'demo');
    cdk.Tags.of(this).add('CostCenter', 'automation');
  }
}

// ========================================
// CDK App Instantiation
// ========================================

const app = new cdk.App();

// Get deployment configuration from context or environment
const projectName = app.node.tryGetContext('projectName') || 'business-automation';
const environment = app.node.tryGetContext('environment') || 'demo';

new BusinessProcessAutomationStack(app, `${projectName}-${environment}`, {
  description: 'Interactive Business Process Automation with Bedrock AgentCore and EventBridge',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Application: 'BusinessProcessAutomation',
    Environment: environment,
    ManagedBy: 'CDK',
  },
});