#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  aws_s3 as s3,
  aws_iam as iam,
  aws_lambda as lambda,
  aws_stepfunctions as sfn,
  aws_stepfunctions_tasks as sfn_tasks,
  aws_sagemaker as sagemaker,
  aws_sns as sns,
  aws_logs as logs,
  Duration,
  RemovalPolicy,
  Stack,
  StackProps,
} from 'aws-cdk-lib';

/**
 * CDK Stack for Machine Learning Pipeline with SageMaker and Step Functions
 * 
 * This stack creates a complete ML pipeline that includes:
 * - S3 bucket for storing data and model artifacts
 * - IAM roles for SageMaker and Step Functions
 * - Lambda function for model evaluation
 * - Step Functions state machine for orchestration
 * - SNS topic for notifications
 */
export class MLPipelineStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for ML pipeline artifacts
    const mlBucket = new s3.Bucket(this, 'MLPipelineBucket', {
      bucketName: `ml-pipeline-bucket-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(30),
        },
      ],
    });

    // Create folder structure in S3 bucket
    ['raw-data/', 'processed-data/', 'model-artifacts/', 'code/'].forEach(folder => {
      new s3.BucketDeployment(this, `CreateFolder${folder.replace(/[^a-zA-Z0-9]/g, '')}`, {
        sources: [s3.Source.data(folder, '')],
        destinationBucket: mlBucket,
        destinationKeyPrefix: folder,
      });
    });

    // Create IAM role for SageMaker
    const sageMakerRole = new iam.Role(this, 'SageMakerExecutionRole', {
      roleName: `SageMakerMLPipelineRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('sagemaker.amazonaws.com'),
      description: 'IAM role for SageMaker ML Pipeline operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess'),
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
                's3:ListBucket',
              ],
              resources: [
                mlBucket.bucketArn,
                `${mlBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        CloudWatchLogs: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogStreams',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for model evaluation
    const modelEvaluationFunction = new lambda.Function(this, 'ModelEvaluationFunction', {
      functionName: `ModelEvaluator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(30),
      memorySize: 128,
      environment: {
        S3_BUCKET: mlBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to evaluate model performance from SageMaker training job output
    """
    s3 = boto3.client('s3')
    
    try:
        # Get training job name and S3 bucket from event
        training_job_name = event['TrainingJobName']
        s3_bucket = event.get('S3Bucket', os.environ['S3_BUCKET'])
        
        logger.info(f"Evaluating model for training job: {training_job_name}")
        
        # Download evaluation metrics from S3
        evaluation_key = f"model-artifacts/{training_job_name}/output/evaluation.json"
        
        try:
            response = s3.get_object(Bucket=s3_bucket, Key=evaluation_key)
            evaluation_data = json.loads(response['Body'].read())
            
            logger.info(f"Retrieved evaluation metrics: {evaluation_data}")
            
            # Add deployment decision logic based on performance thresholds
            test_r2 = evaluation_data.get('test_r2', 0)
            test_rmse = evaluation_data.get('test_rmse', float('inf'))
            
            # Define performance thresholds
            r2_threshold = 0.7
            rmse_threshold = 10.0
            
            deployment_approved = (test_r2 >= r2_threshold and test_rmse <= rmse_threshold)
            
            evaluation_data['deployment_approved'] = deployment_approved
            evaluation_data['r2_threshold'] = r2_threshold
            evaluation_data['rmse_threshold'] = rmse_threshold
            
            logger.info(f"Deployment approved: {deployment_approved}")
            
            return {
                'statusCode': 200,
                'body': evaluation_data
            }
            
        except s3.exceptions.NoSuchKey:
            logger.error(f"Evaluation file not found: {evaluation_key}")
            return {
                'statusCode': 404,
                'body': {'error': f'Evaluation file not found: {evaluation_key}'}
            }
            
    except Exception as e:
        logger.error(f"Error evaluating model: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': str(e)}
        }
      `),
    });

    // Grant Lambda function access to S3 bucket
    mlBucket.grantRead(modelEvaluationFunction);

    // Create SNS topic for notifications
    const notificationTopic = new sns.Topic(this, 'MLPipelineNotifications', {
      topicName: `MLPipelineNotifications-${uniqueSuffix}`,
      displayName: 'ML Pipeline Notifications',
    });

    // Create IAM role for Step Functions
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsExecutionRole', {
      roleName: `StepFunctionsMLRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      description: 'IAM role for Step Functions ML Pipeline orchestration',
      inlinePolicies: {
        SageMakerAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sagemaker:CreateProcessingJob',
                'sagemaker:CreateTrainingJob',
                'sagemaker:CreateModel',
                'sagemaker:CreateEndpointConfig',
                'sagemaker:CreateEndpoint',
                'sagemaker:UpdateEndpoint',
                'sagemaker:DeleteEndpoint',
                'sagemaker:DescribeProcessingJob',
                'sagemaker:DescribeTrainingJob',
                'sagemaker:DescribeModel',
                'sagemaker:DescribeEndpoint',
                'sagemaker:ListTags',
                'sagemaker:AddTags',
              ],
              resources: ['*'],
            }),
          ],
        }),
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                mlBucket.bucketArn,
                `${mlBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        LambdaAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [modelEvaluationFunction.functionArn],
            }),
          ],
        }),
        IAMPassRole: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['iam:PassRole'],
              resources: [sageMakerRole.roleArn],
            }),
          ],
        }),
        SNSPublish: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [notificationTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Group for Step Functions
    const stepFunctionsLogGroup = new logs.LogGroup(this, 'StepFunctionsLogGroup', {
      logGroupName: `/aws/stepfunctions/MLPipeline-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Define Step Functions tasks
    const dataPreprocessingTask = new sfn_tasks.SageMakerCreateProcessingJob(this, 'DataPreprocessing', {
      processingJobName: sfn.JsonPath.stringAt('$.PreprocessingJobName'),
      role: sageMakerRole,
      appSpecification: {
        imageUri: `683313688378.dkr.ecr.${this.region}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3`,
        containerEntrypoint: ['python3', '/opt/ml/processing/input/code/preprocessing.py'],
        containerArguments: [
          '--input-data', '/opt/ml/processing/input/data/train.csv',
          '--output-data', '/opt/ml/processing/output/train_processed.csv',
        ],
      },
      processingInputs: [
        {
          inputName: 'data',
          s3Input: {
            s3Uri: `s3://${mlBucket.bucketName}/raw-data`,
            localPath: '/opt/ml/processing/input/data',
            s3DataType: sfn_tasks.S3DataType.S3_PREFIX,
          },
        },
        {
          inputName: 'code',
          s3Input: {
            s3Uri: `s3://${mlBucket.bucketName}/code`,
            localPath: '/opt/ml/processing/input/code',
            s3DataType: sfn_tasks.S3DataType.S3_PREFIX,
          },
        },
      ],
      processingOutputs: [
        {
          outputName: 'processed_data',
          s3Output: {
            s3Uri: `s3://${mlBucket.bucketName}/processed-data`,
            localPath: '/opt/ml/processing/output',
          },
        },
      ],
      processingResources: {
        instanceCount: 1,
        instanceType: sfn_tasks.InstanceType.of(sfn_tasks.InstanceClass.M5, sfn_tasks.InstanceSize.LARGE),
        volumeSizeInGB: 30,
      },
      integrationPattern: sfn.IntegrationPattern.RUN_JOB,
    });

    const modelTrainingTask = new sfn_tasks.SageMakerCreateTrainingJob(this, 'ModelTraining', {
      trainingJobName: sfn.JsonPath.stringAt('$.TrainingJobName'),
      role: sageMakerRole,
      algorithmSpecification: {
        trainingImage: `683313688378.dkr.ecr.${this.region}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3`,
        trainingInputMode: sfn_tasks.InputMode.FILE,
      },
      inputDataConfig: [
        {
          channelName: 'train',
          dataSource: {
            s3DataSource: {
              s3DataType: sfn_tasks.S3DataType.S3_PREFIX,
              s3Uri: `s3://${mlBucket.bucketName}/processed-data`,
              s3DataDistributionType: sfn_tasks.S3DataDistributionType.FULLY_REPLICATED,
            },
          },
        },
        {
          channelName: 'test',
          dataSource: {
            s3DataSource: {
              s3DataType: sfn_tasks.S3DataType.S3_PREFIX,
              s3Uri: `s3://${mlBucket.bucketName}/raw-data`,
              s3DataDistributionType: sfn_tasks.S3DataDistributionType.FULLY_REPLICATED,
            },
          },
        },
        {
          channelName: 'code',
          dataSource: {
            s3DataSource: {
              s3DataType: sfn_tasks.S3DataType.S3_PREFIX,
              s3Uri: `s3://${mlBucket.bucketName}/code`,
              s3DataDistributionType: sfn_tasks.S3DataDistributionType.FULLY_REPLICATED,
            },
          },
        },
      ],
      outputDataConfig: {
        s3OutputPath: `s3://${mlBucket.bucketName}/model-artifacts`,
      },
      resourceConfig: {
        instanceType: sfn_tasks.InstanceType.of(sfn_tasks.InstanceClass.M5, sfn_tasks.InstanceSize.LARGE),
        instanceCount: 1,
        volumeSizeInGB: 30,
      },
      stoppingCondition: {
        maxRuntime: Duration.hours(1),
      },
      hyperparameters: {
        'sagemaker_program': 'training.py',
        'sagemaker_submit_directory': '/opt/ml/input/data/code',
      },
      integrationPattern: sfn.IntegrationPattern.RUN_JOB,
    });

    const modelEvaluationTask = new sfn_tasks.LambdaInvoke(this, 'ModelEvaluation', {
      lambdaFunction: modelEvaluationFunction,
      payload: sfn.TaskInput.fromObject({
        'TrainingJobName': sfn.JsonPath.stringAt('$.TrainingJobName'),
        'S3Bucket': mlBucket.bucketName,
      }),
      resultPath: '$.EvaluationResult',
    });

    const createModelTask = new sfn_tasks.SageMakerCreateModel(this, 'CreateModel', {
      modelName: sfn.JsonPath.stringAt('$.ModelName'),
      primaryContainer: {
        image: `683313688378.dkr.ecr.${this.region}.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3`,
        modelDataUrl: sfn.JsonPath.stringAt('$.ModelDataUrl'),
        environment: {
          'SAGEMAKER_PROGRAM': 'inference.py',
          'SAGEMAKER_SUBMIT_DIRECTORY': '/opt/ml/code',
        },
      },
      role: sageMakerRole,
    });

    const createEndpointConfigTask = new sfn_tasks.SageMakerCreateEndpointConfig(this, 'CreateEndpointConfig', {
      endpointConfigName: sfn.JsonPath.stringAt('$.EndpointConfigName'),
      productionVariants: [
        {
          variantName: 'primary',
          modelName: sfn.JsonPath.stringAt('$.ModelName'),
          initialInstanceCount: 1,
          instanceType: sfn_tasks.InstanceType.of(sfn_tasks.InstanceClass.T2, sfn_tasks.InstanceSize.MEDIUM),
          initialVariantWeight: 1,
        },
      ],
    });

    const createEndpointTask = new sfn_tasks.SageMakerCreateEndpoint(this, 'CreateEndpoint', {
      endpointName: sfn.JsonPath.stringAt('$.EndpointName'),
      endpointConfigName: sfn.JsonPath.stringAt('$.EndpointConfigName'),
      integrationPattern: sfn.IntegrationPattern.RUN_JOB,
    });

    // Create notification tasks
    const successNotificationTask = new sfn_tasks.SnsPublish(this, 'SuccessNotification', {
      topic: notificationTopic,
      subject: 'ML Pipeline Completed Successfully',
      message: sfn.TaskInput.fromObject({
        'status': 'SUCCESS',
        'message': 'ML Pipeline completed successfully',
        'endpointName': sfn.JsonPath.stringAt('$.EndpointName'),
        'executionArn': sfn.JsonPath.stringAt('$$.Execution.Name'),
      }),
    });

    const failureNotificationTask = new sfn_tasks.SnsPublish(this, 'FailureNotification', {
      topic: notificationTopic,
      subject: 'ML Pipeline Failed',
      message: sfn.TaskInput.fromObject({
        'status': 'FAILED',
        'message': 'ML Pipeline execution failed',
        'error': sfn.JsonPath.stringAt('$.Error'),
        'executionArn': sfn.JsonPath.stringAt('$$.Execution.Name'),
      }),
    });

    // Define success and failure states
    const successState = new sfn.Succeed(this, 'MLPipelineComplete', {
      comment: 'ML Pipeline completed successfully',
    });

    const processingFailedState = new sfn.Fail(this, 'ProcessingJobFailed', {
      error: 'ProcessingJobFailed',
      cause: 'The data preprocessing job failed',
    });

    const trainingFailedState = new sfn.Fail(this, 'TrainingJobFailed', {
      error: 'TrainingJobFailed',
      cause: 'The model training job failed',
    });

    const modelPerformanceInsufficientState = new sfn.Fail(this, 'ModelPerformanceInsufficient', {
      error: 'ModelPerformanceInsufficient',
      cause: 'Model performance does not meet the required threshold',
    });

    // Define the workflow
    const checkModelPerformance = new sfn.Choice(this, 'CheckModelPerformance', {
      comment: 'Check if model performance meets deployment criteria',
    });

    // Chain the workflow together
    const definition = dataPreprocessingTask
      .addCatch(processingFailedState, { errors: ['States.ALL'] })
      .next(modelTrainingTask)
      .addCatch(trainingFailedState, { errors: ['States.ALL'] })
      .next(modelEvaluationTask)
      .next(checkModelPerformance
        .when(
          sfn.Condition.numberGreaterThan('$.EvaluationResult.Payload.body.test_r2', 0.7),
          createModelTask
            .next(createEndpointConfigTask)
            .next(createEndpointTask)
            .next(successNotificationTask)
            .next(successState)
        )
        .otherwise(
          failureNotificationTask
            .next(modelPerformanceInsufficientState)
        )
      );

    // Create the Step Functions state machine
    const stateMachine = new sfn.StateMachine(this, 'MLPipelineStateMachine', {
      stateMachineName: `MLPipeline-${uniqueSuffix}`,
      definition,
      role: stepFunctionsRole,
      logs: {
        destination: stepFunctionsLogGroup,
        level: sfn.LogLevel.ALL,
        includeExecutionData: true,
      },
      tracingEnabled: true,
      timeout: Duration.hours(4),
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: mlBucket.bucketName,
      description: 'S3 bucket for ML pipeline artifacts',
    });

    new cdk.CfnOutput(this, 'SageMakerRoleArn', {
      value: sageMakerRole.roleArn,
      description: 'SageMaker execution role ARN',
    });

    new cdk.CfnOutput(this, 'StepFunctionsRoleArn', {
      value: stepFunctionsRole.roleArn,
      description: 'Step Functions execution role ARN',
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'Step Functions state machine ARN',
    });

    new cdk.CfnOutput(this, 'ModelEvaluationFunctionArn', {
      value: modelEvaluationFunction.functionArn,
      description: 'Model evaluation Lambda function ARN',
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic ARN for pipeline notifications',
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: stepFunctionsLogGroup.logGroupName,
      description: 'CloudWatch log group for Step Functions execution',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'MLPipeline');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'DataScience');
    cdk.Tags.of(this).add('CostCenter', 'ML-Operations');
  }
}

/**
 * CDK App - Entry point for the application
 */
const app = new cdk.App();

// Create the ML Pipeline stack
new MLPipelineStack(app, 'MLPipelineStack', {
  description: 'CDK Stack for Machine Learning Pipeline with SageMaker and Step Functions',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Application: 'MLPipeline',
    CDKVersion: '2.100.0',
  },
});

// Synthesize the CloudFormation template
app.synth();