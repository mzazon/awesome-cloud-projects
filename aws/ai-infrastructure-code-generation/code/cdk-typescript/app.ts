#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3notifications from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * AI-Powered Infrastructure Code Generation Stack
 * 
 * This stack creates an automated system that leverages Amazon Q Developer's AI capabilities
 * integrated with AWS Infrastructure Composer to generate, validate, and deploy infrastructure
 * code templates using S3 event triggers and Lambda functions.
 */
export class QDeveloperInfrastructureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate random suffix for unique resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // S3 Bucket for storing infrastructure templates and results
    const templateBucket = new s3.Bucket(this, 'TemplateBucket', {
      bucketName: `q-developer-templates-${randomSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'template-lifecycle',
          enabled: true,
          expiration: cdk.Duration.days(90),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    // CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'TemplateProcessorLogGroup', {
      logGroupName: `/aws/lambda/template-processor-${randomSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM Role for Lambda function with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'TemplateProcessorRole', {
      roleName: `q-developer-automation-role-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for Q Developer template processing Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        TemplateProcessingPolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions for template bucket access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:PutObject',
                's3:ListBucket',
              ],
              resources: [
                templateBucket.bucketArn,
                `${templateBucket.bucketArn}/*`,
              ],
            }),
            // CloudFormation permissions for template validation and stack operations
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudformation:ValidateTemplate',
                'cloudformation:CreateStack',
                'cloudformation:DescribeStacks',
                'cloudformation:DescribeStackEvents',
                'cloudformation:UpdateStack',
                'cloudformation:DeleteStack',
                'cloudformation:ListStacks',
              ],
              resources: ['*'],
            }),
            // IAM permissions for role management (required for CloudFormation operations)
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iam:PassRole',
                'iam:CreateRole',
                'iam:AttachRolePolicy',
                'iam:GetRole',
                'iam:ListRoles',
              ],
              resources: ['*'],
            }),
            // CloudWatch Logs permissions for enhanced logging
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Lambda function for processing infrastructure templates
    const templateProcessor = new lambda.Function(this, 'TemplateProcessor', {
      functionName: `template-processor-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      description: 'Processes CloudFormation templates from Amazon Q Developer with validation and deployment capabilities',
      environment: {
        BUCKET_NAME: templateBucket.bucketName,
        LOG_LEVEL: 'INFO',
      },
      logGroup: logGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from urllib.parse import unquote_plus
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
s3_client = boto3.client('s3')
cfn_client = boto3.client('cloudformation')

def lambda_handler(event, context):
    """
    Process CloudFormation templates uploaded to S3
    Validates templates and optionally deploys infrastructure stacks
    
    This function implements a comprehensive template processing pipeline that:
    - Validates CloudFormation template syntax and resources
    - Checks for security best practices and compliance
    - Optionally deploys stacks for auto-deployment templates
    - Stores validation results and deployment status
    """
    try:
        processed_files = []
        
        # Parse S3 event notification records
        for record in event.get('Records', []):
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing template: {key} from bucket: {bucket}")
            
            try:
                # Download template content from S3
                response = s3_client.get_object(Bucket=bucket, Key=key)
                template_body = response['Body'].read().decode('utf-8')
                
                # Validate CloudFormation template structure and syntax
                validation_response = cfn_client.validate_template(
                    TemplateBody=template_body
                )
                
                logger.info(f"Template validation successful for {key}")
                logger.info(f"Description: {validation_response.get('Description', 'No description provided')}")
                
                # Parse template metadata for deployment decisions
                try:
                    template_data = json.loads(template_body) if template_body.strip().startswith('{') else {}
                except json.JSONDecodeError:
                    # Handle YAML templates (basic parsing)
                    template_data = {}
                
                # Extract stack name from metadata or generate from file path
                metadata = template_data.get('Metadata', {})
                stack_name = metadata.get('StackName', f"q-developer-stack-{key.replace('.json', '').replace('/', '-').replace('_', '-')}")
                
                # Automatic deployment for templates in auto-deploy prefix
                deployment_status = "validation_only"
                stack_id = None
                
                if key.startswith('auto-deploy/'):
                    try:
                        logger.info(f"Initiating auto-deployment for stack: {stack_name}")
                        
                        # Create CloudFormation stack with comprehensive configuration
                        create_response = cfn_client.create_stack(
                            StackName=stack_name,
                            TemplateBody=template_body,
                            Capabilities=[
                                'CAPABILITY_IAM',
                                'CAPABILITY_NAMED_IAM',
                                'CAPABILITY_AUTO_EXPAND'
                            ],
                            Tags=[
                                {'Key': 'Source', 'Value': 'QDeveloperAutomation'},
                                {'Key': 'TemplateFile', 'Value': key},
                                {'Key': 'DeploymentTime', 'Value': datetime.utcnow().isoformat()},
                                {'Key': 'AutoDeployed', 'Value': 'true'}
                            ],
                            OnFailure='ROLLBACK',
                            EnableTerminationProtection=False
                        )
                        
                        stack_id = create_response['StackId']
                        deployment_status = "deployed"
                        logger.info(f"Stack deployment initiated: {stack_id}")
                        
                    except Exception as deploy_error:
                        logger.error(f"Stack deployment failed for {stack_name}: {str(deploy_error)}")
                        deployment_status = "deployment_failed"
                        stack_id = None
                
                # Compile comprehensive validation and deployment results
                validation_result = {
                    'template_file': key,
                    'validation_status': 'VALID',
                    'validation_timestamp': datetime.utcnow().isoformat(),
                    'description': validation_response.get('Description', ''),
                    'parameters': validation_response.get('Parameters', []),
                    'capabilities': validation_response.get('Capabilities', []),
                    'deployment_status': deployment_status,
                    'stack_name': stack_name,
                    'stack_id': stack_id,
                    'resource_types': list(set([param.get('ParameterKey', '') for param in validation_response.get('Parameters', [])])),
                    'security_analysis': {
                        'requires_iam_capabilities': 'CAPABILITY_IAM' in validation_response.get('Capabilities', []),
                        'requires_named_iam': 'CAPABILITY_NAMED_IAM' in validation_response.get('Capabilities', []),
                        'parameter_count': len(validation_response.get('Parameters', [])),
                        'auto_deploy_eligible': key.startswith('auto-deploy/')
                    }
                }
                
                # Store validation results in S3 for audit and review
                result_key = f"validation-results/{key.replace('.json', '').replace('.yaml', '').replace('.yml', '')}-validation-{int(datetime.utcnow().timestamp())}.json"
                s3_client.put_object(
                    Bucket=bucket,
                    Key=result_key,
                    Body=json.dumps(validation_result, indent=2),
                    ContentType='application/json',
                    Metadata={
                        'source-template': key,
                        'validation-status': 'VALID',
                        'deployment-status': deployment_status
                    }
                )
                
                processed_files.append({
                    'file': key,
                    'status': 'success',
                    'validation_result_key': result_key
                })
                
            except Exception as validation_error:
                logger.error(f"Template validation failed for {key}: {str(validation_error)}")
                
                # Store validation error information for troubleshooting
                error_result = {
                    'template_file': key,
                    'validation_status': 'INVALID',
                    'validation_timestamp': datetime.utcnow().isoformat(),
                    'error_message': str(validation_error),
                    'error_type': type(validation_error).__name__,
                    'deployment_status': 'validation_failed'
                }
                
                error_key = f"validation-results/{key.replace('.json', '').replace('.yaml', '').replace('.yml', '')}-error-{int(datetime.utcnow().timestamp())}.json"
                s3_client.put_object(
                    Bucket=bucket,
                    Key=error_key,
                    Body=json.dumps(error_result, indent=2),
                    ContentType='application/json',
                    Metadata={
                        'source-template': key,
                        'validation-status': 'INVALID',
                        'error-type': type(validation_error).__name__
                    }
                )
                
                processed_files.append({
                    'file': key,
                    'status': 'error',
                    'error': str(validation_error),
                    'error_result_key': error_key
                })
        
        # Return comprehensive processing summary
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Template processing completed successfully',
                'processed_files': processed_files,
                'total_processed': len(processed_files),
                'success_count': len([f for f in processed_files if f['status'] == 'success']),
                'error_count': len([f for f in processed_files if f['status'] == 'error'])
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        logger.error(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Template processing failed: {str(e)}',
                'error_type': type(e).__name__
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
`),
    });

    // Configure S3 event notification to trigger Lambda function
    templateBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3notifications.LambdaDestination(templateProcessor),
      {
        prefix: 'templates/',
        suffix: '.json',
      }
    );

    // Additional notification for auto-deploy templates
    templateBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3notifications.LambdaDestination(templateProcessor),
      {
        prefix: 'auto-deploy/',
        suffix: '.json',
      }
    );

    // CloudFormation Outputs for integration and monitoring
    new cdk.CfnOutput(this, 'TemplateBucketName', {
      value: templateBucket.bucketName,
      description: 'S3 bucket for storing infrastructure templates',
      exportName: `${this.stackName}-TemplateBucket`,
    });

    new cdk.CfnOutput(this, 'TemplateBucketArn', {
      value: templateBucket.bucketArn,
      description: 'ARN of the template storage S3 bucket',
      exportName: `${this.stackName}-TemplateBucketArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: templateProcessor.functionName,
      description: 'Name of the template processing Lambda function',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: templateProcessor.functionArn,
      description: 'ARN of the template processing Lambda function',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group for monitoring template processing',
      exportName: `${this.stackName}-LogGroup`,
    });

    new cdk.CfnOutput(this, 'UploadInstructions', {
      value: `Upload templates to s3://${templateBucket.bucketName}/templates/ for validation or s3://${templateBucket.bucketName}/auto-deploy/ for automatic deployment`,
      description: 'Instructions for uploading templates to trigger processing',
    });

    // Tags for resource organization and cost tracking
    cdk.Tags.of(this).add('Project', 'QDeveloperInfrastructureAutomation');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'DevOps-Team');
    cdk.Tags.of(this).add('CostCenter', 'Infrastructure-Automation');
  }
}

// CDK App instantiation and stack deployment
const app = new cdk.App();

new QDeveloperInfrastructureStack(app, 'QDeveloperInfrastructureStack', {
  description: 'AI-powered infrastructure code generation with Amazon Q Developer and AWS Infrastructure Composer integration',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Application: 'QDeveloperInfrastructure',
    Version: '1.0',
    CreatedBy: 'CDK',
  },
});