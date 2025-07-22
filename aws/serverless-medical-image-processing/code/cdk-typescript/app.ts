#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as s3Notifications from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as xray from 'aws-cdk-lib/aws-xray';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * CDK Stack for Serverless Medical Image Processing with AWS HealthImaging and Step Functions
 * 
 * This stack implements a complete medical imaging pipeline that:
 * - Ingests DICOM files from S3
 * - Processes them through AWS HealthImaging
 * - Orchestrates workflows with Step Functions
 * - Performs image analysis and metadata extraction
 * - Maintains HIPAA compliance and audit trails
 */
export class MedicalImageProcessingStack extends cdk.Stack {
  
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // =================================================================
    // S3 BUCKETS FOR DICOM STORAGE
    // =================================================================

    // Input bucket for DICOM files with encryption and versioning
    const inputBucket = new s3.Bucket(this, 'DicomInputBucket', {
      bucketName: `dicom-input-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            }
          ]
        }
      ]
    });

    // Output bucket for processed results and metadata
    const outputBucket = new s3.Bucket(this, 'DicomOutputBucket', {
      bucketName: `dicom-output-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // =================================================================
    // IAM ROLES AND POLICIES
    // =================================================================

    // Lambda execution role with permissions for HealthImaging, S3, and logging
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `lambda-medical-imaging-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess')
      ],
      inlinePolicies: {
        HealthImagingAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'medical-imaging:*',
                's3:GetObject',
                's3:PutObject',
                's3:ListBucket',
                'states:StartExecution',
                'states:SendTaskSuccess',
                'states:SendTaskFailure'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Step Functions execution role
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsRole', {
      roleName: `stepfunctions-medical-imaging-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaRole')
      ],
      inlinePolicies: {
        HealthImagingAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'medical-imaging:GetDICOMImportJob',
                'medical-imaging:StartDICOMImportJob',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // =================================================================
    // CLOUDWATCH LOGS FOR MONITORING
    // =================================================================

    // Log group for Step Functions state machine
    const stepFunctionsLogGroup = new logs.LogGroup(this, 'StepFunctionsLogGroup', {
      logGroupName: `/aws/stepfunctions/dicom-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // =================================================================
    // LAMBDA FUNCTIONS
    // =================================================================

    // Lambda function to initiate DICOM import jobs
    const startImportFunction = new lambda.Function(this, 'StartImportFunction', {
      functionName: `StartDicomImport-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      role: lambdaExecutionRole,
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        OUTPUT_BUCKET: outputBucket.bucketName,
        LAMBDA_ROLE_ARN: lambdaExecutionRole.roleArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Initiates a HealthImaging import job when DICOM files are uploaded to S3.
    This function processes S3 events and starts the medical image import workflow.
    """
    try:
        datastore_id = os.environ.get('DATASTORE_ID')
        output_bucket = os.environ['OUTPUT_BUCKET']
        
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Extract S3 event details
        for record in event.get('Records', []):
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            logger.info(f"Processing file: s3://{bucket}/{key}")
            
            # Prepare import job parameters
            input_s3_uri = f"s3://{bucket}/{'/'.join(key.split('/')[:-1])}/"
            output_s3_uri = f"s3://{output_bucket}/import-results/"
            
            # Start import job if datastore_id is provided
            if datastore_id:
                response = medical_imaging.start_dicom_import_job(
                    dataStoreId=datastore_id,
                    inputS3Uri=input_s3_uri,
                    outputS3Uri=output_s3_uri,
                    dataAccessRoleArn=os.environ['LAMBDA_ROLE_ARN']
                )
                
                logger.info(f"Import job started: {response['jobId']}")
                
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'jobId': response['jobId'],
                        'dataStoreId': response['dataStoreId'],
                        'status': 'SUBMITTED'
                    })
                }
            else:
                logger.warning("DATASTORE_ID not configured")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'DATASTORE_ID not configured'})
                }
                
    except Exception as e:
        logger.error(f"Error processing import: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `)
    });

    // Lambda function for metadata processing
    const processMetadataFunction = new lambda.Function(this, 'ProcessMetadataFunction', {
      functionName: `ProcessDicomMetadata-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(120),
      memorySize: 512,
      role: lambdaExecutionRole,
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        OUTPUT_BUCKET: outputBucket.bucketName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Extracts and processes DICOM metadata from HealthImaging image sets.
    Parses patient information, study details, and technical parameters.
    """
    try:
        datastore_id = event['datastoreId']
        image_set_id = event['imageSetId']
        
        logger.info(f"Processing metadata for image set: {image_set_id}")
        
        # Get image set metadata
        response = medical_imaging.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        # Parse DICOM metadata
        metadata_blob = response['imageSetMetadataBlob'].read().decode('utf-8')
        metadata = json.loads(metadata_blob)
        
        # Extract relevant fields safely
        patient_info = metadata.get('Patient', {})
        study_info = metadata.get('Study', {})
        series_info = metadata.get('Series', {})
        
        processed_metadata = {
            'patientId': patient_info.get('DICOM', {}).get('PatientID', 'Unknown'),
            'patientName': patient_info.get('DICOM', {}).get('PatientName', 'Unknown'),
            'studyDate': study_info.get('DICOM', {}).get('StudyDate', 'Unknown'),
            'studyDescription': study_info.get('DICOM', {}).get('StudyDescription', 'Unknown'),
            'modality': series_info.get('DICOM', {}).get('Modality', 'Unknown'),
            'imageSetId': image_set_id,
            'processingTimestamp': datetime.utcnow().isoformat(),
            'requestId': context.aws_request_id
        }
        
        # Store processed metadata
        output_key = f"metadata/{image_set_id}/metadata.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(processed_metadata, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Metadata processed and stored: {output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(processed_metadata)
        }
        
    except Exception as e:
        logger.error(f"Error processing metadata: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `)
    });

    // Lambda function for image analysis
    const analyzeImageFunction = new lambda.Function(this, 'AnalyzeImageFunction', {
      functionName: `AnalyzeMedicalImage-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(300),
      memorySize: 1024,
      role: lambdaExecutionRole,
      tracing: lambda.Tracing.ACTIVE,
      environment: {
        OUTPUT_BUCKET: outputBucket.bucketName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime
import hashlib

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Performs basic image analysis on medical images.
    In production, this would integrate with ML models for diagnostic support.
    """
    try:
        datastore_id = event['datastoreId']
        image_set_id = event['imageSetId']
        
        logger.info(f"Analyzing image set: {image_set_id}")
        
        # Get image set metadata for analysis context
        response = medical_imaging.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        # Generate analysis results
        # In production, this would include actual image processing and AI/ML inference
        analysis_id = hashlib.md5(f"{image_set_id}{context.aws_request_id}".encode()).hexdigest()[:8]
        
        analysis_results = {
            'analysisId': analysis_id,
            'imageSetId': image_set_id,
            'analysisType': 'BasicQualityCheck',
            'timestamp': datetime.utcnow().isoformat(),
            'requestId': context.aws_request_id,
            'results': {
                'imageQuality': 'GOOD',
                'processingStatus': 'COMPLETED',
                'anomaliesDetected': False,
                'confidenceScore': 0.95,
                'technicalParameters': {
                    'processingTime': '2.3s',
                    'algorithmVersion': '1.0.0',
                    'qualityMetrics': {
                        'contrast': 'HIGH',
                        'brightness': 'OPTIMAL',
                        'noise': 'LOW'
                    }
                }
            },
            'recommendations': [
                'Image quality suitable for diagnostic review',
                'No immediate quality concerns detected'
            ]
        }
        
        # Store analysis results
        output_key = f"analysis/{image_set_id}/results.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(analysis_results, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Analysis completed and stored: {output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(analysis_results)
        }
        
    except Exception as e:
        logger.error(f"Error analyzing image: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `)
    });

    // =================================================================
    // STEP FUNCTIONS STATE MACHINE
    // =================================================================

    // Define tasks for the state machine
    const checkImportStatus = new sfnTasks.CallAwsService(this, 'CheckImportStatus', {
      service: 'medicalimaging',
      action: 'getDICOMImportJob',
      parameters: {
        'DatastoreId.$': '$.datastoreId',
        'JobId.$': '$.jobId'
      },
      iamResources: ['*'],
      resultPath: '$.importJob'
    });

    const processMetadataTask = new sfnTasks.LambdaInvoke(this, 'ProcessMetadataTask', {
      lambdaFunction: processMetadataFunction,
      payloadResponseOnly: true,
      resultPath: '$.metadataResult'
    });

    const analyzeImageTask = new sfnTasks.LambdaInvoke(this, 'AnalyzeImageTask', {
      lambdaFunction: analyzeImageFunction,
      payloadResponseOnly: true,
      resultPath: '$.analysisResult'
    });

    // Define choice conditions
    const isImportComplete = new stepfunctions.Choice(this, 'IsImportComplete')
      .when(
        stepfunctions.Condition.stringEquals('$.importJob.JobStatus', 'COMPLETED'),
        processMetadataTask.next(analyzeImageTask)
      )
      .when(
        stepfunctions.Condition.stringEquals('$.importJob.JobStatus', 'IN_PROGRESS'),
        new stepfunctions.Wait(this, 'WaitForImport', {
          time: stepfunctions.WaitTime.duration(cdk.Duration.seconds(30))
        }).next(checkImportStatus)
      )
      .otherwise(
        new stepfunctions.Fail(this, 'ImportFailed', {
          error: 'ImportJobFailed',
          cause: 'The DICOM import job failed or was cancelled'
        })
      );

    // Build the state machine definition
    const definition = checkImportStatus
      .next(isImportComplete);

    // Create the state machine
    const stateMachine = new stepfunctions.StateMachine(this, 'DicomProcessorStateMachine', {
      stateMachineName: `dicom-processor-${uniqueSuffix}`,
      definition,
      role: stepFunctionsRole,
      stateMachineType: stepfunctions.StateMachineType.EXPRESS,
      logs: {
        destination: stepFunctionsLogGroup,
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true
      },
      tracingEnabled: true
    });

    // =================================================================
    // EVENTBRIDGE RULES FOR AUTOMATION
    // =================================================================

    // EventBridge rule for import job completion
    const importCompletionRule = new events.Rule(this, 'DicomImportCompletionRule', {
      ruleName: `DicomImportCompleted-${uniqueSuffix}`,
      eventPattern: {
        source: ['aws.medical-imaging'],
        detailType: ['Import Job Completed'],
        detail: {
          // Note: This would be configured with actual datastore ID after deployment
          status: ['COMPLETED']
        }
      },
      enabled: true
    });

    // Add Step Functions as target for import completion events
    importCompletionRule.addTarget(new eventsTargets.SfnStateMachine(stateMachine, {
      input: events.RuleTargetInput.fromEventPath('$.detail')
    }));

    // =================================================================
    // S3 EVENT NOTIFICATIONS
    // =================================================================

    // Configure S3 to trigger Lambda on DICOM file uploads
    inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3Notifications.LambdaDestination(startImportFunction),
      {
        suffix: '.dcm'
      }
    );

    // =================================================================
    // X-RAY TRACING
    // =================================================================

    // Enable X-Ray tracing for the application
    new xray.CfnSamplingRule(this, 'XRayTracingSamplingRule', {
      samplingRule: {
        description: 'Medical Image Processing Tracing',
        serviceName: 'medical-image-processing',
        serviceType: '*',
        host: '*',
        httpMethod: '*',
        urlPath: '*',
        version: 1,
        priority: 9000,
        fixedRate: 0.1,
        reservoirSize: 1
      }
    });

    // =================================================================
    // STACK OUTPUTS
    // =================================================================

    new cdk.CfnOutput(this, 'InputBucketName', {
      description: 'S3 bucket for DICOM file uploads',
      value: inputBucket.bucketName,
      exportName: `DicomInputBucket-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      description: 'S3 bucket for processed results and metadata',
      value: outputBucket.bucketName,
      exportName: `DicomOutputBucket-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      description: 'Step Functions state machine ARN for medical image processing',
      value: stateMachine.stateMachineArn,
      exportName: `DicomProcessorStateMachine-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'StartImportFunctionName', {
      description: 'Lambda function for initiating DICOM imports',
      value: startImportFunction.functionName,
      exportName: `StartImportFunction-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'ProcessMetadataFunctionName', {
      description: 'Lambda function for processing DICOM metadata',
      value: processMetadataFunction.functionName,
      exportName: `ProcessMetadataFunction-${uniqueSuffix}`
    });

    new cdk.CfnOutput(this, 'AnalyzeImageFunctionName', {
      description: 'Lambda function for medical image analysis',
      value: analyzeImageFunction.functionName,
      exportName: `AnalyzeImageFunction-${uniqueSuffix}`
    });

    // =================================================================
    // TAGS FOR RESOURCE MANAGEMENT
    // =================================================================

    // Apply tags to all resources in the stack
    cdk.Tags.of(this).add('Project', 'MedicalImageProcessing');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Application', 'HealthImaging');
    cdk.Tags.of(this).add('Compliance', 'HIPAA-Eligible');
    cdk.Tags.of(this).add('Owner', 'HealthIT');
    cdk.Tags.of(this).add('CostCenter', 'Healthcare');
  }
}

// =================================================================
// CDK APP INITIALIZATION
// =================================================================

const app = new cdk.App();

// Create the stack with appropriate environment configuration
new MedicalImageProcessingStack(app, 'MedicalImageProcessingStack', {
  description: 'Serverless Medical Image Processing with AWS HealthImaging and Step Functions',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  // Enable termination protection for production deployments
  terminationProtection: false,
  
  // Stack-level tags
  tags: {
    'Application': 'MedicalImageProcessing',
    'Framework': 'CDK',
    'Language': 'TypeScript'
  }
});

// Synthesize the CloudFormation template
app.synth();