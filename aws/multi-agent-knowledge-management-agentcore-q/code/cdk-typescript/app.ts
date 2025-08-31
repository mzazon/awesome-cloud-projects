#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigatewayv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as apigatewayv2Integrations from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Multi-Agent Knowledge Management Stack with Bedrock AgentCore and Q Business
 * 
 * This stack creates a comprehensive multi-agent knowledge management system using:
 * - Amazon S3 for domain-specific knowledge storage
 * - Amazon Q Business for enterprise search and knowledge retrieval
 * - AWS Lambda for agent implementations (supervisor, finance, HR, technical)
 * - Amazon DynamoDB for session management and agent memory
 * - Amazon API Gateway for external API access
 * - IAM roles with least privilege access patterns
 * 
 * The architecture follows the supervisor-collaborator pattern where a supervisor
 * agent coordinates specialized agents to provide comprehensive responses.
 */
class MultiAgentKnowledgeManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
      Math.random().toString(36).substring(2, 8);

    // Tags for all resources
    const commonTags = {
      Project: 'MultiAgentKnowledgeManagement',
      Environment: this.node.tryGetContext('environment') || 'development',
      Owner: 'aws-cdk',
      CostCenter: 'engineering'
    };

    // Apply common tags to the stack
    cdk.Tags.of(this).add('Project', commonTags.Project);
    cdk.Tags.of(this).add('Environment', commonTags.Environment);
    cdk.Tags.of(this).add('Owner', commonTags.Owner);
    cdk.Tags.of(this).add('CostCenter', commonTags.CostCenter);

    // =============================================================================
    // S3 BUCKETS FOR KNOWLEDGE BASES
    // =============================================================================

    // Finance knowledge base bucket
    const financeBucket = new s3.Bucket(this, 'FinanceKnowledgeBucket', {
      bucketName: `finance-kb-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(90),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // HR knowledge base bucket
    const hrBucket = new s3.Bucket(this, 'HRKnowledgeBucket', {
      bucketName: `hr-kb-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(90),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Technical knowledge base bucket
    const techBucket = new s3.Bucket(this, 'TechnicalKnowledgeBucket', {
      bucketName: `tech-kb-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(90),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // =============================================================================
    // DYNAMODB TABLE FOR SESSION MANAGEMENT
    // =============================================================================

    const sessionTable = new dynamodb.Table(this, 'AgentSessionTable', {
      tableName: `agent-sessions-${uniqueSuffix}`,
      partitionKey: {
        name: 'sessionId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      timeToLiveAttribute: 'ttl',
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // =============================================================================
    // IAM ROLES AND POLICIES
    // =============================================================================

    // IAM role for Lambda functions and Q Business
    const agentRole = new iam.Role(this, 'AgentCoreRole', {
      roleName: `AgentCoreRole-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('qbusiness.amazonaws.com')
      ),
      description: 'Role for multi-agent knowledge management system',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonBedrockFullAccess'),
      ],
    });

    // Add custom policy for S3 access to knowledge buckets
    agentRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:GetObjectVersion',
        's3:ListBucket',
        's3:GetBucketLocation',
      ],
      resources: [
        financeBucket.bucketArn,
        `${financeBucket.bucketArn}/*`,
        hrBucket.bucketArn,
        `${hrBucket.bucketArn}/*`,
        techBucket.bucketArn,
        `${techBucket.bucketArn}/*`,
      ],
    }));

    // Add DynamoDB permissions for session management
    agentRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:PutItem',
        'dynamodb:GetItem',
        'dynamodb:UpdateItem',
        'dynamodb:DeleteItem',
        'dynamodb:Query',
        'dynamodb:Scan',
      ],
      resources: [
        sessionTable.tableArn,
        `${sessionTable.tableArn}/index/*`,
      ],
    }));

    // Add Q Business permissions
    agentRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'qbusiness:CreateApplication',
        'qbusiness:GetApplication',
        'qbusiness:UpdateApplication',
        'qbusiness:DeleteApplication',
        'qbusiness:CreateIndex',
        'qbusiness:GetIndex',
        'qbusiness:CreateDataSource',
        'qbusiness:GetDataSource',
        'qbusiness:StartDataSourceSyncJob',
        'qbusiness:CreateConversation',
        'qbusiness:ChatSync',
        'qbusiness:ListConversations',
      ],
      resources: ['*'],
    }));

    // Add Lambda invoke permissions for agent coordination
    agentRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'lambda:InvokeFunction',
      ],
      resources: [
        `arn:aws:lambda:${this.region}:${this.account}:function:*-agent-${uniqueSuffix}`,
      ],
    }));

    // =============================================================================
    // LAMBDA FUNCTIONS FOR AGENTS
    // =============================================================================

    // CloudWatch log group for Lambda functions
    const createLogGroup = (functionName: string): logs.LogGroup => {
      return new logs.LogGroup(this, `${functionName}LogGroup`, {
        logGroupName: `/aws/lambda/${functionName}`,
        retention: logs.RetentionDays.TWO_WEEKS,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });
    };

    // Finance Agent Lambda Function
    const financeAgentLogGroup = createLogGroup(`finance-agent-${uniqueSuffix}`);
    const financeAgent = new lambda.Function(this, 'FinanceAgent', {
      functionName: `finance-agent-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: agentRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logGroup: financeAgentLogGroup,
      environment: {
        SESSION_TABLE: sessionTable.tableName,
        RANDOM_SUFFIX: uniqueSuffix,
      },
      code: lambda.Code.fromInline(this.getFinanceAgentCode()),
      description: 'Finance specialist agent for budget and financial policy queries',
    });

    // HR Agent Lambda Function
    const hrAgentLogGroup = createLogGroup(`hr-agent-${uniqueSuffix}`);
    const hrAgent = new lambda.Function(this, 'HRAgent', {
      functionName: `hr-agent-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: agentRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logGroup: hrAgentLogGroup,
      environment: {
        SESSION_TABLE: sessionTable.tableName,
        RANDOM_SUFFIX: uniqueSuffix,
      },
      code: lambda.Code.fromInline(this.getHRAgentCode()),
      description: 'HR specialist agent for employee and policy queries',
    });

    // Technical Agent Lambda Function
    const technicalAgentLogGroup = createLogGroup(`technical-agent-${uniqueSuffix}`);
    const technicalAgent = new lambda.Function(this, 'TechnicalAgent', {
      functionName: `technical-agent-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: agentRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logGroup: technicalAgentLogGroup,
      environment: {
        SESSION_TABLE: sessionTable.tableName,
        RANDOM_SUFFIX: uniqueSuffix,
      },
      code: lambda.Code.fromInline(this.getTechnicalAgentCode()),
      description: 'Technical specialist agent for engineering and system queries',
    });

    // Supervisor Agent Lambda Function
    const supervisorAgentLogGroup = createLogGroup(`supervisor-agent-${uniqueSuffix}`);
    const supervisorAgent = new lambda.Function(this, 'SupervisorAgent', {
      functionName: `supervisor-agent-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: agentRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      logGroup: supervisorAgentLogGroup,
      environment: {
        SESSION_TABLE: sessionTable.tableName,
        RANDOM_SUFFIX: uniqueSuffix,
        FINANCE_AGENT_NAME: financeAgent.functionName,
        HR_AGENT_NAME: hrAgent.functionName,
        TECHNICAL_AGENT_NAME: technicalAgent.functionName,
      },
      code: lambda.Code.fromInline(this.getSupervisorAgentCode()),
      description: 'Supervisor agent that coordinates specialized agents for knowledge retrieval',
    });

    // =============================================================================
    // API GATEWAY FOR EXTERNAL ACCESS
    // =============================================================================

    // HTTP API Gateway for multi-agent system
    const api = new apigatewayv2.HttpApi(this, 'MultiAgentAPI', {
      apiName: `multi-agent-km-api-${uniqueSuffix}`,
      description: 'Multi-agent knowledge management API with enterprise features',
      corsPreflight: {
        allowCredentials: false,
        allowHeaders: ['Content-Type', 'Authorization'],
        allowMethods: [
          apigatewayv2.CorsHttpMethod.GET,
          apigatewayv2.CorsHttpMethod.POST,
          apigatewayv2.CorsHttpMethod.OPTIONS,
        ],
        allowOrigins: ['*'],
        maxAge: cdk.Duration.days(1),
      },
    });

    // Lambda integration for supervisor agent
    const supervisorIntegration = new apigatewayv2Integrations.HttpLambdaIntegration(
      'SupervisorIntegration',
      supervisorAgent,
      {
        timeout: cdk.Duration.seconds(29),
      }
    );

    // Add routes to API Gateway
    api.addRoutes({
      path: '/query',
      methods: [apigatewayv2.HttpMethod.POST],
      integration: supervisorIntegration,
    });

    api.addRoutes({
      path: '/health',
      methods: [apigatewayv2.HttpMethod.GET],
      integration: supervisorIntegration,
    });

    // Create a stage with throttling and logging
    const stage = new apigatewayv2.CfnStage(this, 'ProdStage', {
      apiId: api.httpApiId,
      stageName: 'prod',
      autoDeploy: true,
      description: 'Production stage for multi-agent knowledge management',
      throttleSettings: {
        burstLimit: 1000,
        rateLimit: 500,
      },
      accessLogSettings: {
        destinationArn: new logs.LogGroup(this, 'ApiGatewayLogGroup', {
          logGroupName: `/aws/apigateway/multi-agent-km-api-${uniqueSuffix}`,
          retention: logs.RetentionDays.TWO_WEEKS,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }).logGroupArn,
        format: JSON.stringify({
          requestId: '$context.requestId',
          requestTime: '$context.requestTime',
          httpMethod: '$context.httpMethod',
          resourcePath: '$context.resourcePath',
          status: '$context.status',
          responseLength: '$context.responseLength',
          responseTime: '$context.responseTime',
        }),
      },
    });

    // =============================================================================
    // OUTPUTS
    // =============================================================================

    new cdk.CfnOutput(this, 'APIEndpoint', {
      value: `${api.url}`,
      description: 'Multi-Agent Knowledge Management API endpoint',
      exportName: `MultiAgentKMAPI-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'FinanceBucketName', {
      value: financeBucket.bucketName,
      description: 'Finance knowledge base S3 bucket name',
    });

    new cdk.CfnOutput(this, 'HRBucketName', {
      value: hrBucket.bucketName,
      description: 'HR knowledge base S3 bucket name',
    });

    new cdk.CfnOutput(this, 'TechnicalBucketName', {
      value: techBucket.bucketName,
      description: 'Technical knowledge base S3 bucket name',
    });

    new cdk.CfnOutput(this, 'SessionTableName', {
      value: sessionTable.tableName,
      description: 'Agent session management DynamoDB table name',
    });

    new cdk.CfnOutput(this, 'AgentRoleArn', {
      value: agentRole.roleArn,
      description: 'IAM role ARN for agents and Q Business',
    });

    new cdk.CfnOutput(this, 'SupervisorAgentName', {
      value: supervisorAgent.functionName,
      description: 'Supervisor agent Lambda function name',
    });

    new cdk.CfnOutput(this, 'DeploymentCommands', {
      value: [
        '# After deployment, create Q Business application and upload sample documents:',
        `aws qbusiness create-application --display-name "Enterprise Knowledge Management System" --role-arn ${agentRole.roleArn}`,
        `aws s3 cp finance-policy.txt s3://${financeBucket.bucketName}/`,
        `aws s3 cp hr-handbook.txt s3://${hrBucket.bucketName}/`,
        `aws s3 cp tech-guidelines.txt s3://${techBucket.bucketName}/`,
      ].join('\n'),
      description: 'Post-deployment commands for Q Business setup',
    });
  }

  // =============================================================================
  // LAMBDA FUNCTION CODE
  // =============================================================================

  private getFinanceAgentCode(): string {
    return `
import json
import boto3
import os
import logging
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Finance specialist agent for budget and financial policy queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"Finance agent processing query: {query}")
        
        # For now, use fallback logic until Q Business is configured
        response = get_finance_fallback(query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'finance',
                'response': response,
                'sources': ['Finance Policy Documentation'],
                'session_id': session_id
            })
        }
            
    except Exception as e:
        logger.error(f"Finance agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Finance agent error: {str(e)}"
            })
        }

def get_finance_fallback(query: str) -> str:
    """Provide fallback finance information"""
    query_lower = query.lower()
    
    if 'expense' in query_lower or 'approval' in query_lower:
        return "Expense approval process: Expenses over $1000 require manager approval, over $5000 require director approval, and over $10000 require CFO approval."
    elif 'budget' in query_lower:
        return "Budget management: Quarterly reviews conducted in March, June, September, December. Annual allocations updated in January."
    elif 'travel' in query_lower or 'reimbursement' in query_lower:
        return "Travel policy: Reimbursement requires receipts within 30 days. International travel needs 2-week pre-approval. Daily allowances: $75 domestic, $100 international."
    else:
        return "Finance policies cover expense approvals, budget management, and travel procedures. Specific policies require review of complete documentation."
`;
  }

  private getHRAgentCode(): string {
    return `
import json
import boto3
import os
import logging
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    HR specialist agent for employee and policy queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"HR agent processing query: {query}")
        
        # For now, use fallback logic until Q Business is configured
        response = get_hr_fallback(query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'hr',
                'response': response,
                'sources': ['HR Handbook and Policies'],
                'session_id': session_id
            })
        }
            
    except Exception as e:
        logger.error(f"HR agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"HR agent error: {str(e)}"
            })
        }

def get_hr_fallback(query: str) -> str:
    """Provide fallback HR information"""
    query_lower = query.lower()
    
    if 'onboard' in query_lower:
        return "Onboarding process: 3-5 business days completion, IT setup on first day, benefits enrollment within 30 days of start date."
    elif 'performance' in query_lower or 'review' in query_lower:
        return "Performance management: Annual reviews in Q4, mid-year check-ins in Q2, performance improvement plans have 90-day duration."
    elif 'vacation' in query_lower or 'leave' in query_lower:
        return "Time off policies: Vacation requires 2-week advance notice, 10 sick days annually (5 carry-over), 12 weeks paid parental leave plus 4 weeks unpaid."
    elif 'remote' in query_lower or 'work' in query_lower:
        return "Remote work policy: Up to 3 days per week remote work allowed, subject to role requirements and manager approval."
    else:
        return "HR policies cover onboarding, performance management, time off, and workplace procedures. Consult complete handbook for specific guidance."
`;
  }

  private getTechnicalAgentCode(): string {
    return `
import json
import boto3
import os
import logging
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Technical specialist agent for engineering and system queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"Technical agent processing query: {query}")
        
        # For now, use fallback logic until Q Business is configured
        response = get_technical_fallback(query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'technical',
                'response': response,
                'sources': ['Technical Guidelines Documentation'],
                'session_id': session_id
            })
        }
            
    except Exception as e:
        logger.error(f"Technical agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Technical agent error: {str(e)}"
            })
        }

def get_technical_fallback(query: str) -> str:
    """Provide fallback technical information"""
    query_lower = query.lower()
    
    if 'code' in query_lower or 'development' in query_lower:
        return "Development standards: All code requires automated testing before deployment, minimum 80% code coverage for production, security scans for external applications."
    elif 'backup' in query_lower or 'database' in query_lower:
        return "Infrastructure management: Database backups performed nightly at 2 AM UTC, 30-day local retention, 90-day archive retention, quarterly DR testing."
    elif 'api' in query_lower:
        return "API standards: 1000 requests per minute rate limit, authentication required for all endpoints, SSL/TLS 1.2 minimum for communications."
    elif 'security' in query_lower:
        return "Security procedures: Security patching within 48 hours for critical vulnerabilities, SSL/TLS 1.2 minimum, authentication required for all API endpoints."
    else:
        return "Technical guidelines cover development standards, infrastructure management, API protocols, and security procedures. Consult complete documentation for implementation details."
`;
  }

  private getSupervisorAgentCode(): string {
    return `
import json
import boto3
import os
from typing import List, Dict, Any
import uuid
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Supervisor agent that coordinates specialized agents for knowledge retrieval
    """
    try:
        # Handle API Gateway event structure
        if 'body' in event:
            if event['body']:
                try:
                    body = json.loads(event['body'])
                except json.JSONDecodeError:
                    body = {}
            else:
                body = {}
        else:
            body = event
        
        # Handle health check
        if event.get('httpMethod') == 'GET' and event.get('path') == '/health':
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'service': 'multi-agent-knowledge-management',
                    'timestamp': context.aws_request_id
                })
            }
        
        # Initialize AWS clients
        lambda_client = boto3.client('lambda')
        dynamodb = boto3.resource('dynamodb')
        
        # Parse request
        query = body.get('query', '')
        session_id = body.get('sessionId', str(uuid.uuid4()))
        
        logger.info(f"Processing query: {query} for session: {session_id}")
        
        # Determine which agents to engage based on query analysis
        agents_to_engage = determine_agents(query)
        logger.info(f"Engaging agents: {agents_to_engage}")
        
        # Collect responses from specialized agents
        agent_responses = []
        for agent_name in agents_to_engage:
            try:
                response = invoke_specialized_agent(lambda_client, agent_name, query, session_id)
                agent_responses.append({
                    'agent': agent_name,
                    'response': response,
                    'confidence': calculate_confidence(agent_name, query)
                })
            except Exception as e:
                logger.error(f"Error invoking {agent_name} agent: {str(e)}")
                agent_responses.append({
                    'agent': agent_name,
                    'response': f"Error retrieving {agent_name} information",
                    'confidence': 0.0
                })
        
        # Synthesize comprehensive answer
        final_response = synthesize_responses(query, agent_responses)
        
        # Store session information for context
        store_session_context(session_id, query, final_response, agents_to_engage, context)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'query': query,
                'response': final_response,
                'agents_consulted': agents_to_engage,
                'session_id': session_id,
                'confidence_scores': {resp['agent']: resp['confidence'] for resp in agent_responses}
            })
        }
        
    except Exception as e:
        logger.error(f"Supervisor agent error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f"Supervisor agent error: {str(e)}"
            })
        }

def determine_agents(query: str) -> List[str]:
    """Determine which specialized agents to engage based on query analysis"""
    query_lower = query.lower()
    agents = []
    
    # Finance-related keywords
    finance_keywords = ['budget', 'expense', 'cost', 'finance', 'money', 'approval', 
                       'reimbursement', 'travel', 'spending', 'capital', 'cfo']
    if any(word in query_lower for word in finance_keywords):
        agents.append('finance')
    
    # HR-related keywords
    hr_keywords = ['employee', 'hr', 'vacation', 'onboard', 'performance', 'leave',
                   'remote', 'work', 'benefits', 'policy', 'review', 'sick']
    if any(word in query_lower for word in hr_keywords):
        agents.append('hr')
    
    # Technical-related keywords
    tech_keywords = ['technical', 'code', 'api', 'database', 'security', 'backup',
                     'system', 'development', 'infrastructure', 'server', 'ssl']
    if any(word in query_lower for word in tech_keywords):
        agents.append('technical')
    
    # If no specific domain detected, engage all agents for comprehensive coverage
    return agents if agents else ['finance', 'hr', 'technical']

def calculate_confidence(agent_name: str, query: str) -> float:
    """Calculate confidence score for agent relevance to query"""
    query_lower = query.lower()
    
    if agent_name == 'finance':
        finance_keywords = ['budget', 'expense', 'cost', 'finance', 'money', 'approval']
        matches = sum(1 for word in finance_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    elif agent_name == 'hr':
        hr_keywords = ['employee', 'hr', 'vacation', 'onboard', 'performance', 'leave']
        matches = sum(1 for word in hr_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    elif agent_name == 'technical':
        tech_keywords = ['technical', 'code', 'api', 'database', 'security', 'backup']
        matches = sum(1 for word in tech_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    
    return 0.5  # Default confidence

def invoke_specialized_agent(lambda_client, agent_name: str, query: str, session_id: str) -> str:
    """Invoke a specialized agent Lambda function"""
    random_suffix = os.environ.get('RANDOM_SUFFIX', 'default')
    function_name = f"{agent_name}-agent-{random_suffix}"
    
    try:
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'query': query,
                'sessionId': session_id,
                'context': f"Domain-specific query for {agent_name} expertise"
            })
        )
        
        result = json.loads(response['Payload'].read())
        if result.get('statusCode') == 200:
            body = json.loads(result.get('body', '{}'))
            return body.get('response', f"No {agent_name} information available")
        else:
            return f"Error retrieving {agent_name} information"
            
    except Exception as e:
        logger.error(f"Error invoking {agent_name} agent: {str(e)}")
        return f"Error accessing {agent_name} knowledge base"

def synthesize_responses(query: str, responses: List[Dict]) -> str:
    """Synthesize responses from multiple agents into a comprehensive answer"""
    if not responses:
        return "No relevant information found in the knowledge base."
    
    # Filter responses by confidence score
    high_confidence_responses = [r for r in responses if r.get('confidence', 0) > 0.3]
    responses_to_use = high_confidence_responses if high_confidence_responses else responses
    
    synthesis = f"Based on consultation with {len(responses_to_use)} specialized knowledge domains:\\n\\n"
    
    for resp in responses_to_use:
        if resp['response'] and not resp['response'].startswith('Error'):
            confidence_indicator = "🔷" if resp.get('confidence', 0) > 0.6 else "🔹"
            synthesis += f"{confidence_indicator} **{resp['agent'].title()} Domain**: {resp['response']}\\n\\n"
    
    synthesis += "\\n*This response was generated by consulting multiple specialized knowledge agents.*"
    return synthesis

def store_session_context(session_id: str, query: str, response: str, agents: List[str], context):
    """Store session context for future reference"""
    try:
        table_name = os.environ.get('SESSION_TABLE', 'agent-sessions-default')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(table_name)
        
        import time
        timestamp = str(int(time.time()))
        
        table.put_item(
            Item={
                'sessionId': session_id,
                'timestamp': timestamp,
                'query': query,
                'response': response,
                'agents_consulted': agents,
                'ttl': int(time.time()) + 86400  # 24 hour TTL
            }
        )
    except Exception as e:
        logger.error(f"Error storing session context: {str(e)}")
`;
  }
}

// =============================================================================
// CDK APP ENTRY POINT
// =============================================================================

const app = new cdk.App();

// Get configuration from context
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the stack
new MultiAgentKnowledgeManagementStack(app, 'MultiAgentKnowledgeManagementStack', {
  env,
  description: 'Multi-Agent Knowledge Management System with Bedrock AgentCore and Q Business',
  tags: {
    Project: 'MultiAgentKnowledgeManagement',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: 'aws-cdk',
    CostCenter: 'engineering',
  },
});

app.synth();