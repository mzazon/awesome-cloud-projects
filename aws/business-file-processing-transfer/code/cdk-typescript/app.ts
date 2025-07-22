#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as transfer from 'aws-cdk-lib/aws-transfer';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

/**
 * CDK Stack for automated business file processing using AWS Transfer Family and Step Functions
 * 
 * This stack creates a serverless file processing pipeline that:
 * 1. Receives files via SFTP through AWS Transfer Family
 * 2. Automatically validates, processes, and routes files using Step Functions
 * 3. Stores processed files in organized S3 storage tiers
 * 4. Provides monitoring and alerting for operational visibility
 */
export class FileProcessingStack extends cdk.Stack {
  // S3 Buckets for file storage tiers
  private readonly landingBucket: s3.Bucket;
  private readonly processedBucket: s3.Bucket;
  private readonly archiveBucket: s3.Bucket;

  // Lambda functions for file processing logic
  private readonly validatorFunction: lambda.Function;
  private readonly processorFunction: lambda.Function;
  private readonly routerFunction: lambda.Function;

  // Step Functions state machine for workflow orchestration
  private readonly stateMachine: stepfunctions.StateMachine;

  // Transfer Family SFTP server
  private readonly transferServer: transfer.CfnServer;

  // SNS topic for alerts
  private readonly alertsTopic: sns.Topic;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // Create S3 buckets for file storage tiers
    this.createS3Buckets(uniqueSuffix);

    // Create Lambda functions for file processing
    this.createLambdaFunctions();

    // Create Step Functions workflow
    this.createStepFunctionsWorkflow();

    // Create AWS Transfer Family SFTP server
    this.createTransferFamilyServer();

    // Configure S3 event integration with Step Functions
    this.configureS3Events();

    // Set up monitoring and alerting
    this.setupMonitoring();

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates S3 buckets for different file storage tiers
   * Landing bucket: Initial file uploads from SFTP
   * Processed bucket: Files after business logic processing
   * Archive bucket: Final storage with organized structure
   */
  private createS3Buckets(uniqueSuffix: string): void {
    // Landing bucket for initial file uploads
    this.landingBucket = new s3.Bucket(this, 'LandingBucket', {
      bucketName: `file-processing-${uniqueSuffix}-landing`,
      versioned: true,
      lifecycleRules: [{
        id: 'landing-lifecycle',
        enabled: true,
        transitions: [{
          storageClass: s3.StorageClass.INFREQUENT_ACCESS,
          transitionAfter: cdk.Duration.days(30)
        }]
      }],
      eventBridgeEnabled: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // Processed bucket for files after business processing
    this.processedBucket = new s3.Bucket(this, 'ProcessedBucket', {
      bucketName: `file-processing-${uniqueSuffix}-processed`,
      versioned: true,
      lifecycleRules: [{
        id: 'processed-lifecycle',
        enabled: true,
        transitions: [{
          storageClass: s3.StorageClass.INFREQUENT_ACCESS,
          transitionAfter: cdk.Duration.days(90)
        }]
      }],
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // Archive bucket for long-term organized storage
    this.archiveBucket = new s3.Bucket(this, 'ArchiveBucket', {
      bucketName: `file-processing-${uniqueSuffix}-archive`,
      versioned: true,
      lifecycleRules: [{
        id: 'archive-lifecycle',
        enabled: true,
        transitions: [
          {
            storageClass: s3.StorageClass.INFREQUENT_ACCESS,
            transitionAfter: cdk.Duration.days(30)
          },
          {
            storageClass: s3.StorageClass.GLACIER,
            transitionAfter: cdk.Duration.days(365)
          }
        ]
      }],
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // Tag all buckets for resource management
    cdk.Tags.of(this.landingBucket).add('Purpose', 'FileProcessingLanding');
    cdk.Tags.of(this.processedBucket).add('Purpose', 'FileProcessingProcessed');
    cdk.Tags.of(this.archiveBucket).add('Purpose', 'FileProcessingArchive');
  }

  /**
   * Creates Lambda functions for file processing logic
   * Validator: Validates file format and structure
   * Processor: Applies business transformations
   * Router: Routes files to appropriate destinations
   */
  private createLambdaFunctions(): void {
    // Common Lambda execution role with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:CopyObject',
                's3:DeleteObject'
              ],
              resources: [
                `${this.landingBucket.bucketArn}/*`,
                `${this.processedBucket.bucketArn}/*`,
                `${this.archiveBucket.bucketArn}/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: ['*']
            })
          ]
        })
      }
    });

    // File validator Lambda function
    this.validatorFunction = new lambda.Function(this, 'ValidatorFunction', {
      functionName: `file-processing-${this.node.addr.substring(0, 6)}-validator`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      code: lambda.Code.fromInline(`
import json
import boto3
import csv
from io import StringIO

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    
    # Extract S3 information from EventBridge or direct input
    if 'detail' in event:
        bucket = event['detail']['bucket']['name']
        key = event['detail']['object']['key']
    else:
        bucket = event['bucket']
        key = event['key']
    
    try:
        # Download and validate file format
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Validate CSV format
        csv_reader = csv.reader(StringIO(content))
        rows = list(csv_reader)
        
        if len(rows) < 2:  # Header + at least one data row
            raise ValueError("File must contain header and data rows")
        
        return {
            'statusCode': 200,
            'isValid': True,
            'rowCount': len(rows) - 1,
            'bucket': bucket,
            'key': key
        }
    except Exception as e:
        return {
            'statusCode': 400,
            'isValid': False,
            'error': str(e),
            'bucket': bucket,
            'key': key
        }
      `)
    });

    // Data processor Lambda function
    this.processorFunction = new lambda.Function(this, 'ProcessorFunction', {
      functionName: `file-processing-${this.node.addr.substring(0, 6)}-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(300),
      memorySize: 512,
      code: lambda.Code.fromInline(`
import json
import boto3
import csv
import io
from datetime import datetime

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket = event['bucket']
    key = event['key']
    
    try:
        # Download original file
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Process CSV data
        csv_reader = csv.DictReader(io.StringIO(content))
        processed_rows = []
        
        for row in csv_reader:
            # Add processing timestamp
            row['processed_timestamp'] = datetime.utcnow().isoformat()
            # Add business logic transformations here
            processed_rows.append(row)
        
        # Convert back to CSV
        output = io.StringIO()
        if processed_rows:
            writer = csv.DictWriter(output, fieldnames=processed_rows[0].keys())
            writer.writeheader()
            writer.writerows(processed_rows)
        
        # Upload processed file
        processed_key = f"processed/{key}"
        s3.put_object(
            Bucket=bucket.replace('landing', 'processed'),
            Key=processed_key,
            Body=output.getvalue(),
            ContentType='text/csv'
        )
        
        return {
            'statusCode': 200,
            'processedKey': processed_key,
            'recordCount': len(processed_rows),
            'bucket': bucket,
            'originalKey': key
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'bucket': bucket,
            'key': key
        }
      `)
    });

    // File router Lambda function
    this.routerFunction = new lambda.Function(this, 'RouterFunction', {
      functionName: `file-processing-${this.node.addr.substring(0, 6)}-router`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(180),
      memorySize: 256,
      code: lambda.Code.fromInline(`
import json
import boto3

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    
    bucket = event['bucket']
    key = event['processedKey']
    record_count = event['recordCount']
    
    try:
        # Determine routing destination based on file content
        if 'financial' in key.lower():
            destination = 'financial-data/'
        elif 'inventory' in key.lower():
            destination = 'inventory-data/'
        else:
            destination = 'general-data/'
        
        # Copy to appropriate destination
        processed_bucket = bucket.replace('landing', 'processed')
        archive_bucket = bucket.replace('landing', 'archive')
        
        # Copy to archive with organized structure
        archive_key = f"{destination}{key}"
        s3.copy_object(
            CopySource={'Bucket': processed_bucket, 'Key': key},
            Bucket=archive_bucket,
            Key=archive_key
        )
        
        return {
            'statusCode': 200,
            'destination': destination,
            'archiveKey': archive_key,
            'recordCount': record_count
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e)
        }
      `)
    });
  }

  /**
   * Creates Step Functions state machine for workflow orchestration
   * Implements validation, processing, and routing with error handling
   */
  private createStepFunctionsWorkflow(): void {
    // Create execution role for Step Functions
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsRole', {
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      inlinePolicies: {
        LambdaInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [
                this.validatorFunction.functionArn,
                this.processorFunction.functionArn,
                this.routerFunction.functionArn
              ]
            })
          ]
        })
      }
    });

    // Define workflow tasks
    const validateTask = new sfnTasks.LambdaInvoke(this, 'ValidateFile', {
      lambdaFunction: this.validatorFunction,
      outputPath: '$.Payload',
      retryOnServiceExceptions: true
    });

    const processTask = new sfnTasks.LambdaInvoke(this, 'ProcessFile', {
      lambdaFunction: this.processorFunction,
      outputPath: '$.Payload',
      retryOnServiceExceptions: true
    });

    const routeTask = new sfnTasks.LambdaInvoke(this, 'RouteFile', {
      lambdaFunction: this.routerFunction,
      outputPath: '$.Payload'
    });

    // Define workflow states
    const validationCheck = new stepfunctions.Choice(this, 'CheckValidation')
      .when(
        stepfunctions.Condition.booleanEquals('$.isValid', true),
        processTask.next(routeTask).next(new stepfunctions.Succeed(this, 'ProcessingComplete'))
      )
      .otherwise(new stepfunctions.Fail(this, 'ValidationFailed', {
        cause: 'File validation failed'
      }));

    // Create state machine
    const definition = validateTask.next(validationCheck);

    this.stateMachine = new stepfunctions.StateMachine(this, 'FileProcessingWorkflow', {
      stateMachineName: `file-processing-${this.node.addr.substring(0, 6)}-workflow`,
      definition,
      role: stepFunctionsRole,
      logs: {
        destination: new cdk.aws_logs.LogGroup(this, 'WorkflowLogGroup', {
          logGroupName: `/aws/stepfunctions/file-processing-${this.node.addr.substring(0, 6)}`,
          retention: cdk.aws_logs.RetentionDays.TWO_WEEKS,
          removalPolicy: cdk.RemovalPolicy.DESTROY
        }),
        level: stepfunctions.LogLevel.ALL
      },
      tracingEnabled: true
    });
  }

  /**
   * Creates AWS Transfer Family SFTP server with S3 integration
   */
  private createTransferFamilyServer(): void {
    // Create IAM role for Transfer Family
    const transferRole = new iam.Role(this, 'TransferRole', {
      assumedBy: new iam.ServicePrincipal('transfer.amazonaws.com'),
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:GetObjectVersion',
                's3:DeleteObject',
                's3:DeleteObjectVersion'
              ],
              resources: [`${this.landingBucket.bucketArn}/*`]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:ListBucket',
                's3:GetBucketLocation'
              ],
              resources: [this.landingBucket.bucketArn]
            })
          ]
        })
      }
    });

    // Create Transfer Family SFTP server
    this.transferServer = new transfer.CfnServer(this, 'SFTPServer', {
      identityProviderType: 'SERVICE_MANAGED',
      protocols: ['SFTP'],
      endpointType: 'PUBLIC',
      tags: [
        { key: 'Name', value: `file-processing-${this.node.addr.substring(0, 6)}-sftp` },
        { key: 'Purpose', value: 'FileProcessing' }
      ]
    });

    // Create SFTP user for business partners
    new transfer.CfnUser(this, 'BusinessPartnerUser', {
      serverId: this.transferServer.attrServerId,
      userName: 'businesspartner',
      role: transferRole.roleArn,
      homeDirectory: `/${this.landingBucket.bucketName}`,
      homeDirectoryType: 'PATH',
      tags: [
        { key: 'UserType', value: 'BusinessPartner' },
        { key: 'Purpose', value: 'FileUpload' }
      ]
    });
  }

  /**
   * Configures S3 event integration with Step Functions
   */
  private configureS3Events(): void {
    // Create EventBridge role for Step Functions execution
    const eventBridgeRole = new iam.Role(this, 'EventBridgeRole', {
      assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
      inlinePolicies: {
        StepFunctionsExecutePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['states:StartExecution'],
              resources: [this.stateMachine.stateMachineArn]
            })
          ]
        })
      }
    });

    // Create EventBridge rule for S3 object creation events
    const s3EventRule = new events.Rule(this, 'S3FileProcessingRule', {
      ruleName: `file-processing-${this.node.addr.substring(0, 6)}-s3-events`,
      eventPattern: {
        source: ['aws.s3'],
        detailType: ['Object Created'],
        detail: {
          bucket: {
            name: [this.landingBucket.bucketName]
          }
        }
      },
      enabled: true
    });

    // Add Step Functions as target for S3 events
    s3EventRule.addTarget(new eventsTargets.SfnStateMachine(this.stateMachine, {
      role: eventBridgeRole
    }));
  }

  /**
   * Sets up monitoring and alerting for the file processing pipeline
   */
  private setupMonitoring(): void {
    // Create SNS topic for alerts
    this.alertsTopic = new sns.Topic(this, 'AlertsTopic', {
      topicName: `file-processing-${this.node.addr.substring(0, 6)}-alerts`,
      displayName: 'File Processing Alerts'
    });

    // Create CloudWatch alarm for failed Step Functions executions
    const failedExecutionsAlarm = new cloudwatch.Alarm(this, 'FailedExecutionsAlarm', {
      alarmName: `file-processing-${this.node.addr.substring(0, 6)}-failed-executions`,
      alarmDescription: 'Alert on Step Functions execution failures',
      metric: this.stateMachine.metricFailed({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
    });

    // Add SNS notification to alarm
    failedExecutionsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));

    // Create alarm for Lambda function errors
    const lambdaErrorsAlarm = new cloudwatch.Alarm(this, 'LambdaErrorsAlarm', {
      alarmName: `file-processing-${this.node.addr.substring(0, 6)}-lambda-errors`,
      alarmDescription: 'Alert on Lambda function errors',
      metric: new cloudwatch.MathExpression({
        expression: 'errors1 + errors2 + errors3',
        usingMetrics: {
          errors1: this.validatorFunction.metricErrors(),
          errors2: this.processorFunction.metricErrors(),
          errors3: this.routerFunction.metricErrors()
        },
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      evaluationPeriods: 1
    });

    lambdaErrorsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));
  }

  /**
   * Creates CloudFormation outputs for important resource information
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'LandingBucketName', {
      value: this.landingBucket.bucketName,
      description: 'S3 bucket for initial file uploads',
      exportName: `${this.stackName}-LandingBucket`
    });

    new cdk.CfnOutput(this, 'ProcessedBucketName', {
      value: this.processedBucket.bucketName,
      description: 'S3 bucket for processed files',
      exportName: `${this.stackName}-ProcessedBucket`
    });

    new cdk.CfnOutput(this, 'ArchiveBucketName', {
      value: this.archiveBucket.bucketName,
      description: 'S3 bucket for archived files',
      exportName: `${this.stackName}-ArchiveBucket`
    });

    new cdk.CfnOutput(this, 'SFTPServerEndpoint', {
      value: `${this.transferServer.attrServerId}.server.transfer.${this.region}.amazonaws.com`,
      description: 'SFTP server endpoint for file uploads',
      exportName: `${this.stackName}-SFTPEndpoint`
    });

    new cdk.CfnOutput(this, 'SFTPServerId', {
      value: this.transferServer.attrServerId,
      description: 'Transfer Family server ID',
      exportName: `${this.stackName}-SFTPServerId`
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: this.stateMachine.stateMachineArn,
      description: 'Step Functions state machine ARN',
      exportName: `${this.stackName}-StateMachineArn`
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: this.alertsTopic.topicArn,
      description: 'SNS topic for monitoring alerts',
      exportName: `${this.stackName}-AlertsTopic`
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the file processing stack
new FileProcessingStack(app, 'FileProcessingStack', {
  description: 'Automated business file processing with AWS Transfer Family and Step Functions',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'FileProcessing',
    Purpose: 'AutomatedFileProcessing',
    Environment: 'Development'
  }
});

// Synthesize the CloudFormation template
app.synth();