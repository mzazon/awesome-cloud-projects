#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kendra from 'aws-cdk-lib/aws-kendra';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';

/**
 * Props for the IntelligentDocumentQAStack
 */
interface IntelligentDocumentQAStackProps extends cdk.StackProps {
  /** Unique suffix for resource naming */
  readonly resourceSuffix?: string;
  /** Environment name (dev, staging, prod) */
  readonly environment?: string;
  /** Enable API Gateway (default: true) */
  readonly enableApiGateway?: boolean;
  /** Bedrock model ID to use for generating answers */
  readonly bedrockModelId?: string;
}

/**
 * CDK Stack for Intelligent Document QA System using AWS Bedrock and Amazon Kendra
 * 
 * This stack deploys:
 * - S3 bucket for document storage
 * - Amazon Kendra index for intelligent search
 * - Lambda function for QA processing with Bedrock integration
 * - API Gateway for RESTful access (optional)
 * - Necessary IAM roles and policies
 */
export class IntelligentDocumentQAStack extends cdk.Stack {
  // Public properties for accessing key resources
  public readonly documentsBucket: s3.Bucket;
  public readonly kendraIndex: kendra.CfnIndex;
  public readonly qaLambdaFunction: lambda.Function;
  public readonly apiGateway?: apigateway.RestApi;

  constructor(scope: Construct, id: string, props: IntelligentDocumentQAStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const resourceSuffix = props.resourceSuffix || this.generateRandomSuffix();
    const environment = props.environment || 'dev';
    const enableApiGateway = props.enableApiGateway ?? true;
    const bedrockModelId = props.bedrockModelId || 'anthropic.claude-3-sonnet-20240229-v1:0';

    // Tags for all resources
    const commonTags = {
      Project: 'IntelligentDocumentQA',
      Environment: environment,
      ManagedBy: 'CDK'
    };

    // Apply common tags to the stack
    cdk.Tags.of(this).add('Project', commonTags.Project);
    cdk.Tags.of(this).add('Environment', commonTags.Environment);
    cdk.Tags.of(this).add('ManagedBy', commonTags.ManagedBy);

    // S3 Bucket for document storage
    this.documentsBucket = new s3.Bucket(this, 'DocumentsBucket', {
      bucketName: `intelligent-qa-documents-${resourceSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - remove in production
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        }
      ]
    });

    // Create folder structure in S3 bucket
    new s3deploy.BucketDeployment(this, 'DocumentFolders', {
      sources: [s3deploy.Source.data('documents/', '')], // Creates documents/ prefix
      destinationBucket: this.documentsBucket,
      destinationKeyPrefix: 'documents/',
    });

    // IAM Role for Kendra
    const kendraServiceRole = new iam.Role(this, 'KendraServiceRole', {
      roleName: `KendraServiceRole-${resourceSuffix}`,
      assumedBy: new iam.ServicePrincipal('kendra.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess')
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:ListBucket'
              ],
              resources: [
                this.documentsBucket.bucketArn,
                `${this.documentsBucket.bucketArn}/*`
              ]
            })
          ]
        })
      }
    });

    // CloudWatch Log Group for Kendra
    const kendraLogGroup = new logs.LogGroup(this, 'KendraLogGroup', {
      logGroupName: `/aws/kendra/index/${resourceSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Amazon Kendra Index
    this.kendraIndex = new kendra.CfnIndex(this, 'KendraIndex', {
      name: `qa-system-${resourceSuffix}`,
      roleArn: kendraServiceRole.roleArn,
      edition: 'DEVELOPER_EDITION', // Use ENTERPRISE_EDITION for production
      description: 'Intelligent document search index for QA system',
      documentMetadataConfigurations: [
        {
          name: '_source_uri',
          type: 'STRING_VALUE',
          search: {
            displayable: true,
            facetable: false,
            searchable: false
          }
        },
        {
          name: '_document_title',
          type: 'STRING_VALUE',
          search: {
            displayable: true,
            facetable: false,
            searchable: true
          }
        }
      ],
      tags: [
        { key: 'Name', value: `qa-system-${resourceSuffix}` },
        { key: 'Project', value: commonTags.Project },
        { key: 'Environment', value: commonTags.Environment }
      ]
    });

    // S3 Data Source for Kendra
    const kendraDataSource = new kendra.CfnDataSource(this, 'KendraS3DataSource', {
      indexId: this.kendraIndex.attrId,
      name: 'S3DocumentSource',
      type: 'S3',
      roleArn: kendraServiceRole.roleArn,
      dataSourceConfiguration: {
        s3Configuration: {
          bucketName: this.documentsBucket.bucketName,
          inclusionPrefixes: ['documents/'],
          documentsMetadataConfiguration: {
            s3Prefix: 'metadata/'
          }
        }
      },
      description: 'S3 data source for document ingestion',
      tags: [
        { key: 'Name', value: 'S3DocumentSource' },
        { key: 'Project', value: commonTags.Project },
        { key: 'Environment', value: commonTags.Environment }
      ]
    });

    // IAM Role for Lambda Function
    const lambdaExecutionRole = new iam.Role(this, 'LambdaQARole', {
      roleName: `LambdaQARole-${resourceSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        QAPermissions: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kendra:Query',
                'kendra:DescribeIndex'
              ],
              resources: [this.kendraIndex.attrArn]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['bedrock:InvokeModel'],
              resources: [`arn:aws:bedrock:${this.region}::foundation-model/${bedrockModelId}`]
            })
          ]
        })
      }
    });

    // Lambda Function for QA Processing
    this.qaLambdaFunction = new lambda.Function(this, 'QAProcessorFunction', {
      functionName: `qa-processor-${resourceSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      environment: {
        KENDRA_INDEX_ID: this.kendraIndex.attrId,
        BEDROCK_MODEL_ID: bedrockModelId,
        LOG_LEVEL: 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
kendra = boto3.client('kendra')
bedrock = boto3.client('bedrock-runtime')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing QA requests
    
    Args:
        event: API Gateway event containing the question
        context: Lambda context object
        
    Returns:
        Dict containing the answer and source citations
    """
    try:
        # Extract question from event
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
            question = body.get('question', '')
        else:
            question = event.get('question', '')
            
        if not question:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Question is required'})
            }
        
        logger.info(f"Processing question: {question}")
        
        # Query Kendra for relevant documents
        kendra_response = query_kendra(question)
        
        # Extract relevant passages
        passages = extract_passages(kendra_response)
        
        if not passages:
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'question': question,
                    'answer': 'I could not find relevant information in the documents to answer your question.',
                    'sources': []
                })
            }
        
        # Generate answer using Bedrock
        answer = generate_answer(question, passages)
        
        # Prepare response
        response = {
            'question': question,
            'answer': answer,
            'sources': [{'title': p['title'], 'uri': p['uri']} for p in passages]
        }
        
        logger.info("Successfully processed QA request")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(response)
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }

def query_kendra(question: str) -> Dict[str, Any]:
    """Query Kendra index for relevant documents"""
    index_id = os.environ['KENDRA_INDEX_ID']
    
    response = kendra.query(
        IndexId=index_id,
        QueryText=question,
        PageSize=5,
        AttributeFilter={
            'EqualsTo': {
                'Key': '_language_code',
                'Value': {'StringValue': 'en'}
            }
        }
    )
    
    return response

def extract_passages(kendra_response: Dict[str, Any]) -> List[Dict[str, str]]:
    """Extract relevant text passages from Kendra response"""
    passages = []
    
    for item in kendra_response.get('ResultItems', []):
        if item.get('Type') == 'DOCUMENT':
            passage = {
                'text': item.get('DocumentExcerpt', {}).get('Text', ''),
                'title': item.get('DocumentTitle', {}).get('Text', 'Untitled Document'),
                'uri': item.get('DocumentURI', '')
            }
            if passage['text']:  # Only include if there's actual text content
                passages.append(passage)
    
    return passages

def generate_answer(question: str, passages: List[Dict[str, str]]) -> str:
    """Generate answer using Bedrock Claude model"""
    model_id = os.environ['BEDROCK_MODEL_ID']
    
    # Prepare context from passages
    context_text = '\\n\\n'.join([
        f"Document: {p['title']}\\n{p['text']}" 
        for p in passages
    ])
    
    # Create prompt for Claude
    prompt = f"""Based on the following document excerpts, please answer this question: {question}

Document excerpts:
{context_text}

Please provide a comprehensive answer based only on the information in the documents. If the documents don't contain enough information to answer the question, please say so. Include relevant citations by referencing the document titles.

Answer:"""
    
    # Call Bedrock
    response = bedrock.invoke_model(
        modelId=model_id,
        body=json.dumps({
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': 1000,
            'messages': [{'role': 'user', 'content': prompt}],
            'temperature': 0.1
        })
    )
    
    # Parse response
    response_body = json.loads(response['body'].read())
    answer = response_body['content'][0]['text']
    
    return answer
`),
      description: 'Lambda function for processing document QA requests using Kendra and Bedrock'
    });

    // API Gateway (optional)
    if (enableApiGateway) {
      this.apiGateway = new apigateway.RestApi(this, 'QASystemAPI', {
        restApiName: `qa-system-api-${resourceSuffix}`,
        description: 'REST API for Intelligent Document QA System',
        defaultCorsPreflightOptions: {
          allowOrigins: apigateway.Cors.ALL_ORIGINS,
          allowMethods: apigateway.Cors.ALL_METHODS,
          allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key']
        },
        deployOptions: {
          stageName: environment,
          tracingEnabled: true,
          loggingLevel: apigateway.MethodLoggingLevel.INFO,
          dataTraceEnabled: true
        }
      });

      // Create /qa resource
      const qaResource = this.apiGateway.root.addResource('qa');
      
      // Add POST method for QA requests
      const qaIntegration = new apigateway.LambdaIntegration(this.qaLambdaFunction, {
        requestTemplates: { 'application/json': '{ "statusCode": "200" }' }
      });

      qaResource.addMethod('POST', qaIntegration, {
        apiKeyRequired: false,
        methodResponses: [
          {
            statusCode: '200',
            responseModels: {
              'application/json': apigateway.Model.EMPTY_MODEL
            },
            responseParameters: {
              'method.response.header.Access-Control-Allow-Origin': true
            }
          },
          {
            statusCode: '400',
            responseModels: {
              'application/json': apigateway.Model.ERROR_MODEL
            }
          },
          {
            statusCode: '500',
            responseModels: {
              'application/json': apigateway.Model.ERROR_MODEL
            }
          }
        ]
      });

      // Add GET method for health check
      qaResource.addMethod('GET', new apigateway.MockIntegration({
        integrationResponses: [{
          statusCode: '200',
          responseTemplates: {
            'application/json': JSON.stringify({ 
              message: 'QA System API is healthy',
              timestamp: new Date().toISOString()
            })
          }
        }],
        requestTemplates: {
          'application/json': '{ "statusCode": "200" }'
        }
      }), {
        methodResponses: [{
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL
          }
        }]
      });
    }

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'DocumentsBucketName', {
      value: this.documentsBucket.bucketName,
      description: 'Name of the S3 bucket for document storage',
      exportName: `${this.stackName}-DocumentsBucket`
    });

    new cdk.CfnOutput(this, 'KendraIndexId', {
      value: this.kendraIndex.attrId,
      description: 'ID of the Amazon Kendra index',
      exportName: `${this.stackName}-KendraIndexId`
    });

    new cdk.CfnOutput(this, 'QALambdaFunctionName', {
      value: this.qaLambdaFunction.functionName,
      description: 'Name of the QA processing Lambda function',
      exportName: `${this.stackName}-QALambdaFunction`
    });

    if (this.apiGateway) {
      new cdk.CfnOutput(this, 'APIGatewayURL', {
        value: this.apiGateway.url,
        description: 'URL of the API Gateway endpoint',
        exportName: `${this.stackName}-APIGatewayURL`
      });

      new cdk.CfnOutput(this, 'QAEndpoint', {
        value: `${this.apiGateway.url}qa`,
        description: 'Full URL for the QA endpoint',
        exportName: `${this.stackName}-QAEndpoint`
      });
    }

    new cdk.CfnOutput(this, 'ResourceSuffix', {
      value: resourceSuffix,
      description: 'Random suffix used for resource naming',
      exportName: `${this.stackName}-ResourceSuffix`
    });
  }

  /**
   * Generate a random suffix for resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

// CDK Application
const app = new cdk.App();

// Get context values or use defaults
const environment = app.node.tryGetContext('environment') || 'dev';
const resourceSuffix = app.node.tryGetContext('resourceSuffix');
const enableApiGateway = app.node.tryGetContext('enableApiGateway') !== 'false';
const bedrockModelId = app.node.tryGetContext('bedrockModelId') || 'anthropic.claude-3-sonnet-20240229-v1:0';

// Deploy the stack
new IntelligentDocumentQAStack(app, 'IntelligentDocumentQAStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  environment,
  resourceSuffix,
  enableApiGateway,
  bedrockModelId,
  description: 'Intelligent Document QA System using AWS Bedrock and Amazon Kendra',
  tags: {
    Project: 'IntelligentDocumentQA',
    Environment: environment,
    ManagedBy: 'CDK'
  }
});

app.synth();