#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as tasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as logs from 'aws-cdk-lib/aws-logs';
import { RemovalPolicy, Duration } from 'aws-cdk-lib';

/**
 * Custom Entity Recognition and Classification Stack
 * 
 * This stack implements a comprehensive custom NLP solution using Amazon Comprehend's
 * custom entity recognition and custom classification capabilities combined with
 * automated training pipelines and real-time inference APIs.
 */
export class ComprehendCustomNlpStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // S3 Bucket for training data and models
    const modelsBucket = new s3.Bucket(this, 'ComprehendModelsBucket', {
      bucketName: `comprehend-models-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'ModelArtifactsCleanup',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90)
            }
          ]
        }
      ]
    });

    // DynamoDB table for storing inference results
    const resultsTable = new dynamodb.Table(this, 'InferenceResultsTable', {
      tableName: `comprehend-results-${uniqueSuffix}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      timeToLiveAttribute: 'ttl'
    });

    // Add GSI for querying by text hash
    resultsTable.addGlobalSecondaryIndex({
      indexName: 'text-hash-index',
      partitionKey: {
        name: 'textHash',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.NUMBER
      }
    });

    // CloudWatch Log Groups
    const preprocessorLogGroup = new logs.LogGroup(this, 'DataPreprocessorLogGroup', {
      logGroupName: `/aws/lambda/comprehend-${uniqueSuffix}-data-preprocessor`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY
    });

    const trainerLogGroup = new logs.LogGroup(this, 'ModelTrainerLogGroup', {
      logGroupName: `/aws/lambda/comprehend-${uniqueSuffix}-model-trainer`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY
    });

    const statusCheckerLogGroup = new logs.LogGroup(this, 'StatusCheckerLogGroup', {
      logGroupName: `/aws/lambda/comprehend-${uniqueSuffix}-status-checker`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY
    });

    const inferenceLogGroup = new logs.LogGroup(this, 'InferenceApiLogGroup', {
      logGroupName: `/aws/lambda/comprehend-${uniqueSuffix}-inference-api`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // IAM Role for Comprehend training jobs
    const comprehendRole = new iam.Role(this, 'ComprehendRole', {
      roleName: `ComprehendCustomRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('comprehend.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ComprehendServiceRole-DataAccessRole')
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket'
              ],
              resources: [
                modelsBucket.bucketArn,
                `${modelsBucket.bucketArn}/*`
              ]
            })
          ]
        })
      }
    });

    // IAM Role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `ComprehendLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        ComprehendAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'comprehend:*'
              ],
              resources: ['*']
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket'
              ],
              resources: [
                modelsBucket.bucketArn,
                `${modelsBucket.bucketArn}/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem'
              ],
              resources: [
                resultsTable.tableArn,
                `${resultsTable.tableArn}/index/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iam:PassRole'
              ],
              resources: [comprehendRole.roleArn]
            })
          ]
        })
      }
    });

    // Lambda function for data preprocessing
    const dataPreprocessor = new lambda.Function(this, 'DataPreprocessorFunction', {
      functionName: `comprehend-${uniqueSuffix}-data-preprocessor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      memorySize: 512,
      logGroup: preprocessorLogGroup,
      environment: {
        BUCKET_NAME: modelsBucket.bucketName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import csv
from io import StringIO
import re
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket = event['bucket']
    entity_key = event['entity_training_data']
    classification_key = event['classification_training_data']
    
    try:
        logger.info(f"Processing training data from bucket: {bucket}")
        
        # Process entity training data
        entity_result = process_entity_data(bucket, entity_key)
        logger.info(f"Entity processing result: {entity_result}")
        
        # Process classification training data
        classification_result = process_classification_data(bucket, classification_key)
        logger.info(f"Classification processing result: {classification_result}")
        
        return {
            'statusCode': 200,
            'entity_training_ready': entity_result,
            'classification_training_ready': classification_result,
            'bucket': bucket
        }
        
    except Exception as e:
        logger.error(f"Error processing training data: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }

def process_entity_data(bucket, key):
    # Download and validate entity training data
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parse CSV and validate format
        csv_reader = csv.DictReader(StringIO(content))
        rows = list(csv_reader)
        
        # Validate required columns
        required_columns = ['Text', 'File', 'Line', 'BeginOffset', 'EndOffset', 'Type']
        if not all(col in csv_reader.fieldnames for col in required_columns):
            raise ValueError(f"Missing required columns. Expected: {required_columns}")
        
        # Validate entity types and counts
        entity_types = {}
        for row in rows:
            entity_type = row['Type']
            entity_types[entity_type] = entity_types.get(entity_type, 0) + 1
        
        # Check minimum examples per entity type
        min_examples = 5  # Reduced for demo purposes
        insufficient_types = [et for et, count in entity_types.items() if count < min_examples]
        
        if insufficient_types:
            logger.warning(f"Entity types with fewer than {min_examples} examples: {insufficient_types}")
        
        # Save processed data
        processed_key = key.replace('.csv', '_processed.csv')
        s3.put_object(
            Bucket=bucket,
            Key=processed_key,
            Body=content,
            ContentType='text/csv'
        )
        
        return {
            'processed_file': processed_key,
            'entity_types': list(entity_types.keys()),
            'total_examples': len(rows),
            'entity_counts': entity_types
        }
        
    except Exception as e:
        logger.error(f"Error processing entity data: {str(e)}")
        raise

def process_classification_data(bucket, key):
    # Download and validate classification training data
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parse CSV and validate format
        csv_reader = csv.DictReader(StringIO(content))
        rows = list(csv_reader)
        
        # Validate required columns
        required_columns = ['Text', 'Label']
        if not all(col in csv_reader.fieldnames for col in required_columns):
            raise ValueError(f"Missing required columns. Expected: {required_columns}")
        
        # Validate labels and counts
        label_counts = {}
        for row in rows:
            label = row['Label']
            label_counts[label] = label_counts.get(label, 0) + 1
        
        # Check minimum examples per label
        min_examples = 5  # Reduced for demo purposes
        insufficient_labels = [label for label, count in label_counts.items() if count < min_examples]
        
        if insufficient_labels:
            logger.warning(f"Labels with fewer than {min_examples} examples: {insufficient_labels}")
        
        # Save processed data
        processed_key = key.replace('.csv', '_processed.csv')
        s3.put_object(
            Bucket=bucket,
            Key=processed_key,
            Body=content,
            ContentType='text/csv'
        )
        
        return {
            'processed_file': processed_key,
            'labels': list(label_counts.keys()),
            'total_examples': len(rows),
            'label_counts': label_counts
        }
        
    except Exception as e:
        logger.error(f"Error processing classification data: {str(e)}")
        raise
`)
    });

    // Lambda function for model training
    const modelTrainer = new lambda.Function(this, 'ModelTrainerFunction', {
      functionName: `comprehend-${uniqueSuffix}-model-trainer`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(1),
      memorySize: 256,
      logGroup: trainerLogGroup,
      environment: {
        COMPREHEND_ROLE_ARN: comprehendRole.roleArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime
import uuid
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    bucket = event['bucket']
    model_type = event['model_type']  # 'entity' or 'classification'
    
    try:
        logger.info(f"Starting {model_type} model training")
        
        if model_type == 'entity':
            result = train_entity_model(event)
        elif model_type == 'classification':
            result = train_classification_model(event)
        else:
            raise ValueError(f"Invalid model type: {model_type}")
        
        logger.info(f"Training job submitted successfully: {result}")
        
        return {
            'statusCode': 200,
            'model_type': model_type,
            'training_job_arn': result['EntityRecognizerArn'] if model_type == 'entity' else result['DocumentClassifierArn'],
            'training_status': 'SUBMITTED'
        }
        
    except Exception as e:
        logger.error(f"Error starting training: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'model_type': model_type
        }

def train_entity_model(event):
    bucket = event['bucket']
    training_data = event['entity_training_ready']['processed_file']
    
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    recognizer_name = f"{event.get('project_name', 'custom')}-entity-{timestamp}"
    
    # Configure training job
    training_config = {
        'RecognizerName': recognizer_name,
        'DataAccessRoleArn': event['role_arn'],
        'InputDataConfig': {
            'EntityTypes': [
                {'Type': entity_type} 
                for entity_type in event['entity_training_ready']['entity_types']
            ],
            'Documents': {
                'S3Uri': f"s3://{bucket}/training-data/entities_sample.txt"
            },
            'Annotations': {
                'S3Uri': f"s3://{bucket}/training-data/{training_data}"
            }
        },
        'LanguageCode': 'en'
    }
    
    # Start training job
    response = comprehend.create_entity_recognizer(**training_config)
    
    return response

def train_classification_model(event):
    bucket = event['bucket']
    training_data = event['classification_training_ready']['processed_file']
    
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    classifier_name = f"{event.get('project_name', 'custom')}-classifier-{timestamp}"
    
    # Configure training job
    training_config = {
        'DocumentClassifierName': classifier_name,
        'DataAccessRoleArn': event['role_arn'],
        'InputDataConfig': {
            'S3Uri': f"s3://{bucket}/training-data/{training_data}"
        },
        'LanguageCode': 'en'
    }
    
    # Start training job
    response = comprehend.create_document_classifier(**training_config)
    
    return response
`)
    });

    // Lambda function for status checking
    const statusChecker = new lambda.Function(this, 'StatusCheckerFunction', {
      functionName: `comprehend-${uniqueSuffix}-status-checker`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.seconds(30),
      memorySize: 256,
      logGroup: statusCheckerLogGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

comprehend = boto3.client('comprehend')

def lambda_handler(event, context):
    model_type = event['model_type']
    job_arn = event['training_job_arn']
    
    try:
        logger.info(f"Checking status for {model_type} model: {job_arn}")
        
        if model_type == 'entity':
            response = comprehend.describe_entity_recognizer(
                EntityRecognizerArn=job_arn
            )
            status = response['EntityRecognizerProperties']['Status']
            
        elif model_type == 'classification':
            response = comprehend.describe_document_classifier(
                DocumentClassifierArn=job_arn
            )
            status = response['DocumentClassifierProperties']['Status']
        
        else:
            raise ValueError(f"Invalid model type: {model_type}")
        
        # Determine if training is complete
        is_complete = status in ['TRAINED', 'TRAINING_FAILED', 'STOPPED']
        
        logger.info(f"Training status: {status}, Complete: {is_complete}")
        
        return {
            'statusCode': 200,
            'model_type': model_type,
            'training_job_arn': job_arn,
            'training_status': status,
            'is_complete': is_complete,
            'model_details': response
        }
        
    except Exception as e:
        logger.error(f"Error checking status: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'model_type': model_type,
            'training_job_arn': job_arn
        }
`)
    });

    // Lambda function for inference API
    const inferenceApi = new lambda.Function(this, 'InferenceApiFunction', {
      functionName: `comprehend-${uniqueSuffix}-inference-api`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.seconds(30),
      memorySize: 512,
      logGroup: inferenceLogGroup,
      environment: {
        RESULTS_TABLE: resultsTable.tableName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime
import uuid
import hashlib
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

comprehend = boto3.client('comprehend')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse request
        body = json.loads(event.get('body', '{}')) if isinstance(event.get('body'), str) else event.get('body', {})
        text = body.get('text', '')
        entity_model_arn = body.get('entity_model_arn')
        classifier_model_arn = body.get('classifier_model_arn')
        
        logger.info(f"Processing inference request for text length: {len(text)}")
        
        if not text:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Text is required'})
            }
        
        results = {}
        
        # Perform entity recognition if model is provided
        if entity_model_arn:
            try:
                entity_results = comprehend.detect_entities(
                    Text=text,
                    EndpointArn=entity_model_arn
                )
                results['entities'] = entity_results['Entities']
                logger.info(f"Entity recognition completed: {len(results['entities'])} entities found")
            except Exception as e:
                logger.warning(f"Entity recognition failed: {str(e)}")
                results['entities'] = []
                results['entity_error'] = str(e)
        
        # Perform classification if model is provided
        if classifier_model_arn:
            try:
                classification_results = comprehend.classify_document(
                    Text=text,
                    EndpointArn=classifier_model_arn
                )
                results['classification'] = classification_results['Classes']
                logger.info(f"Classification completed: {len(results['classification'])} classes found")
            except Exception as e:
                logger.warning(f"Classification failed: {str(e)}")
                results['classification'] = []
                results['classification_error'] = str(e)
        
        # Store results
        if os.environ.get('RESULTS_TABLE'):
            store_results(text, results)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'text': text,
                'results': results,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in inference API: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def store_results(text, results):
    try:
        table_name = os.environ['RESULTS_TABLE']
        table = dynamodb.Table(table_name)
        
        # Generate text hash for deduplication
        text_hash = hashlib.sha256(text.encode()).hexdigest()
        
        item = {
            'id': str(uuid.uuid4()),
            'textHash': text_hash,
            'text': text,
            'results': json.dumps(results),
            'timestamp': int(datetime.now().timestamp()),
            'ttl': int(datetime.now().timestamp()) + (30 * 24 * 60 * 60)  # 30 days
        }
        
        table.put_item(Item=item)
        logger.info("Results stored successfully")
        
    except Exception as e:
        logger.error(f"Error storing results: {str(e)}")
`)
    });

    // Step Functions workflow for training pipeline
    const preprocessTask = new tasks.LambdaInvoke(this, 'PreprocessDataTask', {
      lambdaFunction: dataPreprocessor,
      outputPath: '$.Payload',
      retryOnServiceExceptions: false
    });

    const trainEntityTask = new tasks.LambdaInvoke(this, 'TrainEntityModelTask', {
      lambdaFunction: modelTrainer,
      payload: stepfunctions.TaskInput.fromObject({
        'bucket': modelsBucket.bucketName,
        'model_type': 'entity',
        'project_name': `comprehend-${uniqueSuffix}`,
        'role_arn': comprehendRole.roleArn,
        'entity_training_ready': stepfunctions.JsonPath.objectAt('$.entity_training_ready')
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: false
    });

    const trainClassificationTask = new tasks.LambdaInvoke(this, 'TrainClassificationModelTask', {
      lambdaFunction: modelTrainer,
      payload: stepfunctions.TaskInput.fromObject({
        'bucket': modelsBucket.bucketName,
        'model_type': 'classification',
        'project_name': `comprehend-${uniqueSuffix}`,
        'role_arn': comprehendRole.roleArn,
        'classification_training_ready': stepfunctions.JsonPath.objectAt('$.classification_training_ready')
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: false
    });

    const waitTask = new stepfunctions.Wait(this, 'WaitForTraining', {
      time: stepfunctions.WaitTime.duration(Duration.minutes(5))
    });

    const checkEntityStatusTask = new tasks.LambdaInvoke(this, 'CheckEntityModelStatusTask', {
      lambdaFunction: statusChecker,
      payload: stepfunctions.TaskInput.fromObject({
        'model_type': 'entity',
        'training_job_arn': stepfunctions.JsonPath.stringAt('$.entity_training_result.training_job_arn')
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: false
    });

    const checkClassificationStatusTask = new tasks.LambdaInvoke(this, 'CheckClassificationModelStatusTask', {
      lambdaFunction: statusChecker,
      payload: stepfunctions.TaskInput.fromObject({
        'model_type': 'classification',
        'training_job_arn': stepfunctions.JsonPath.stringAt('$.classification_training_result.training_job_arn')
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: false
    });

    const trainingCompleteState = new stepfunctions.Pass(this, 'TrainingComplete', {
      result: stepfunctions.Result.fromString('Training pipeline completed successfully')
    });

    const checkAllModelsCompleteChoice = new stepfunctions.Choice(this, 'CheckAllModelsComplete')
      .when(
        stepfunctions.Condition.and(
          stepfunctions.Condition.booleanEquals('$.entity_status_result.is_complete', true),
          stepfunctions.Condition.booleanEquals('$.classification_status_result.is_complete', true)
        ),
        trainingCompleteState
      )
      .otherwise(waitTask);

    // Define the workflow
    const definition = preprocessTask
      .next(trainEntityTask.addCatch(new stepfunctions.Pass(this, 'EntityTrainingFailed'), {
        errors: ['States.ALL']
      }))
      .next(trainClassificationTask.addCatch(new stepfunctions.Pass(this, 'ClassificationTrainingFailed'), {
        errors: ['States.ALL']
      }))
      .next(waitTask)
      .next(checkEntityStatusTask)
      .next(checkClassificationStatusTask)
      .next(checkAllModelsCompleteChoice);

    // IAM Role for Step Functions
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsRole', {
      roleName: `ComprehendStepFunctionsRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      inlinePolicies: {
        LambdaInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction'
              ],
              resources: [
                dataPreprocessor.functionArn,
                modelTrainer.functionArn,
                statusChecker.functionArn
              ]
            })
          ]
        })
      }
    });

    // Step Functions State Machine
    const stateMachine = new stepfunctions.StateMachine(this, 'TrainingPipeline', {
      stateMachineName: `comprehend-${uniqueSuffix}-training-pipeline`,
      definition,
      role: stepFunctionsRole,
      timeout: Duration.hours(6),
      logs: {
        destination: new logs.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/comprehend-${uniqueSuffix}-training`,
          retention: logs.RetentionDays.ONE_WEEK,
          removalPolicy: RemovalPolicy.DESTROY
        }),
        level: stepfunctions.LogLevel.ALL
      }
    });

    // API Gateway for inference API
    const api = new apigateway.RestApi(this, 'ComprehendInferenceApi', {
      restApiName: `comprehend-${uniqueSuffix}-inference-api`,
      description: 'API for Comprehend custom model inference',
      deployOptions: {
        stageName: 'prod',
        throttle: {
          rateLimit: 100,
          burstLimit: 200
        },
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'Authorization']
      }
    });

    // API Gateway integration
    const inferenceIntegration = new apigateway.LambdaIntegration(inferenceApi, {
      requestTemplates: {
        'application/json': '$input.body'
      },
      integrationResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': "'*'"
          }
        }
      ]
    });

    // API Gateway resource and method
    const inferenceResource = api.root.addResource('inference');
    inferenceResource.addMethod('POST', inferenceIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': true
          }
        }
      ],
      requestValidator: new apigateway.RequestValidator(this, 'RequestValidator', {
        restApi: api,
        validateRequestBody: true,
        requestValidatorName: 'inference-validator'
      }),
      requestModels: {
        'application/json': new apigateway.Model(this, 'InferenceRequestModel', {
          restApi: api,
          contentType: 'application/json',
          modelName: 'InferenceRequest',
          schema: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              text: {
                type: apigateway.JsonSchemaType.STRING,
                minLength: 1
              },
              entity_model_arn: {
                type: apigateway.JsonSchemaType.STRING
              },
              classifier_model_arn: {
                type: apigateway.JsonSchemaType.STRING
              }
            },
            required: ['text']
          }
        })
      }
    });

    // CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'ComprehendDashboard', {
      dashboardName: `comprehend-${uniqueSuffix}-dashboard`
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Metrics',
        left: [
          dataPreprocessor.metricDuration(),
          modelTrainer.metricDuration(),
          statusChecker.metricDuration(),
          inferenceApi.metricDuration()
        ],
        right: [
          dataPreprocessor.metricErrors(),
          modelTrainer.metricErrors(),
          statusChecker.metricErrors(),
          inferenceApi.metricErrors()
        ]
      }),
      new cloudwatch.GraphWidget({
        title: 'API Gateway Metrics',
        left: [
          api.metricLatency(),
          api.metricCount()
        ],
        right: [
          api.metricClientError(),
          api.metricServerError()
        ]
      }),
      new cloudwatch.GraphWidget({
        title: 'DynamoDB Metrics',
        left: [
          resultsTable.metricConsumedReadCapacityUnits(),
          resultsTable.metricConsumedWriteCapacityUnits()
        ]
      })
    );

    // SNS Topic for notifications
    const notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `comprehend-${uniqueSuffix}-notifications`,
      displayName: 'Comprehend Custom NLP Notifications'
    });

    // CloudWatch Alarms
    new cloudwatch.Alarm(this, 'HighErrorRate', {
      alarmName: `comprehend-${uniqueSuffix}-high-error-rate`,
      metric: inferenceApi.metricErrors(),
      threshold: 10,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    new cloudwatch.Alarm(this, 'HighLatency', {
      alarmName: `comprehend-${uniqueSuffix}-high-latency`,
      metric: api.metricLatency(),
      threshold: 5000, // 5 seconds
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'ModelsBucketName', {
      value: modelsBucket.bucketName,
      description: 'S3 bucket for training data and model artifacts'
    });

    new cdk.CfnOutput(this, 'ResultsTableName', {
      value: resultsTable.tableName,
      description: 'DynamoDB table for inference results'
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'Step Functions state machine for training pipeline'
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'API Gateway endpoint for inference API'
    });

    new cdk.CfnOutput(this, 'InferenceEndpoint', {
      value: `${api.url}inference`,
      description: 'Full inference API endpoint URL'
    });

    new cdk.CfnOutput(this, 'ComprehendRoleArn', {
      value: comprehendRole.roleArn,
      description: 'IAM role ARN for Comprehend training jobs'
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL'
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for notifications'
    });
  }
}

// CDK App
const app = new cdk.App();

new ComprehendCustomNlpStack(app, 'ComprehendCustomNlpStack', {
  description: 'Custom Entity Recognition and Classification with Amazon Comprehend',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'ComprehendCustomNLP',
    Environment: 'Development',
    Owner: 'DataScience',
    CostCenter: 'ML-Platform'
  }
});

app.synth();