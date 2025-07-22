#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sagemaker from 'aws-cdk-lib/aws-sagemaker';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as applicationautoscaling from 'aws-cdk-lib/aws-applicationautoscaling';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the SageMaker ML Model Endpoints Stack
 */
export interface SageMakerMLEndpointsStackProps extends cdk.StackProps {
  /**
   * Name prefix for all resources
   * @default 'ml-endpoints'
   */
  readonly resourcePrefix?: string;

  /**
   * The initial instance type for the SageMaker endpoint
   * @default 'ml.t2.medium'
   */
  readonly instanceType?: string;

  /**
   * Initial number of instances for the endpoint
   * @default 1
   */
  readonly initialInstanceCount?: number;

  /**
   * Minimum number of instances for auto-scaling
   * @default 1
   */
  readonly minCapacity?: number;

  /**
   * Maximum number of instances for auto-scaling
   * @default 5
   */
  readonly maxCapacity?: number;

  /**
   * Target value for invocations per instance metric for auto-scaling
   * @default 70.0
   */
  readonly targetInvocationsPerInstance?: number;

  /**
   * Whether to enable detailed CloudWatch monitoring
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;

  /**
   * S3 bucket prefix for model artifacts
   * @default 'sagemaker-models'
   */
  readonly s3BucketPrefix?: string;

  /**
   * ECR repository name for the inference container
   * @default 'sagemaker-sklearn-inference'
   */
  readonly ecrRepositoryName?: string;
}

/**
 * AWS CDK Stack for SageMaker Model Endpoints for ML Inference
 * 
 * This stack creates:
 * - S3 bucket for model artifacts storage
 * - ECR repository for custom inference containers
 * - IAM roles with appropriate permissions for SageMaker
 * - SageMaker model, endpoint configuration, and endpoint
 * - Auto-scaling configuration for the endpoint
 * - CloudWatch dashboard for monitoring
 */
export class SageMakerMLEndpointsStack extends cdk.Stack {
  public readonly modelBucket: s3.Bucket;
  public readonly ecrRepository: ecr.Repository;
  public readonly sageMakerRole: iam.Role;
  public readonly sageMakerModel: sagemaker.CfnModel;
  public readonly endpointConfig: sagemaker.CfnEndpointConfig;
  public readonly endpoint: sagemaker.CfnEndpoint;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: SageMakerMLEndpointsStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const resourcePrefix = props.resourcePrefix ?? 'ml-endpoints';
    const instanceType = props.instanceType ?? 'ml.t2.medium';
    const initialInstanceCount = props.initialInstanceCount ?? 1;
    const minCapacity = props.minCapacity ?? 1;
    const maxCapacity = props.maxCapacity ?? 5;
    const targetInvocationsPerInstance = props.targetInvocationsPerInstance ?? 70.0;
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;
    const s3BucketPrefix = props.s3BucketPrefix ?? 'sagemaker-models';
    const ecrRepositoryName = props.ecrRepositoryName ?? 'sagemaker-sklearn-inference';

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create S3 bucket for model artifacts
    this.modelBucket = new s3.Bucket(this, 'ModelArtifactsBucket', {
      bucketName: `${s3BucketPrefix}-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          expiration: cdk.Duration.days(30),
          noncurrentVersionExpiration: cdk.Duration.days(7),
        },
      ],
    });

    // Create ECR repository for inference containers
    this.ecrRepository = new ecr.Repository(this, 'InferenceRepository', {
      repositoryName: ecrRepositoryName,
      imageScanOnPush: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      lifecycleRules: [
        {
          description: 'Keep last 10 images',
          maxImageCount: 10,
        },
      ],
    });

    // Create IAM role for SageMaker execution
    this.sageMakerRole = new iam.Role(this, 'SageMakerExecutionRole', {
      roleName: `${resourcePrefix}-execution-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('sagemaker.amazonaws.com'),
      description: 'IAM role for SageMaker model hosting and endpoint management',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerFullAccess'),
      ],
      inlinePolicies: {
        S3ModelAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:ListBucket',
              ],
              resources: [
                this.modelBucket.bucketArn,
                `${this.modelBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        ECRAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecr:GetAuthorizationToken',
                'ecr:BatchCheckLayerAvailability',
                'ecr:GetDownloadUrlForLayer',
                'ecr:BatchGetImage',
              ],
              resources: [
                this.ecrRepository.repositoryArn,
                '*', // ECR authorization token requires wildcard
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
              resources: [
                `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/sagemaker/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch log group for SageMaker endpoint
    const endpointLogGroup = new logs.LogGroup(this, 'EndpointLogGroup', {
      logGroupName: `/aws/sagemaker/Endpoints/${resourcePrefix}-endpoint`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SageMaker Model
    this.sageMakerModel = new sagemaker.CfnModel(this, 'SageMakerModel', {
      modelName: `${resourcePrefix}-model-${uniqueSuffix}`,
      executionRoleArn: this.sageMakerRole.roleArn,
      primaryContainer: {
        image: `${this.account}.dkr.ecr.${this.region}.amazonaws.com/${ecrRepositoryName}:latest`,
        modelDataUrl: `s3://${this.modelBucket.bucketName}/model.tar.gz`,
        environment: {
          SAGEMAKER_PROGRAM: 'predictor.py',
          SAGEMAKER_SUBMIT_DIRECTORY: '/opt/ml/code',
          SAGEMAKER_CONTAINER_LOG_LEVEL: '20',
          SAGEMAKER_REGION: this.region,
        },
      },
      tags: [
        {
          key: 'Project',
          value: 'ML-Model-Endpoints',
        },
        {
          key: 'Environment',
          value: 'Development',
        },
      ],
    });

    // Create SageMaker Endpoint Configuration
    this.endpointConfig = new sagemaker.CfnEndpointConfig(this, 'EndpointConfig', {
      endpointConfigName: `${resourcePrefix}-config-${uniqueSuffix}`,
      productionVariants: [
        {
          variantName: 'primary',
          modelName: this.sageMakerModel.modelName!,
          initialInstanceCount: initialInstanceCount,
          instanceType: instanceType,
          initialVariantWeight: 1.0,
          acceleratorType: undefined, // Can be set to GPU accelerator if needed
        },
      ],
      dataCaptureConfig: enableDetailedMonitoring ? {
        enableCapture: true,
        initialSamplingPercentage: 100,
        destinationS3Uri: `s3://${this.modelBucket.bucketName}/data-capture/`,
        captureOptions: [
          { captureMode: 'Input' },
          { captureMode: 'Output' },
        ],
        captureContentTypeHeader: {
          jsonContentTypes: ['application/json'],
        },
      } : undefined,
      tags: [
        {
          key: 'Project',
          value: 'ML-Model-Endpoints',
        },
        {
          key: 'Environment',
          value: 'Development',
        },
      ],
    });

    // Add dependency to ensure model is created before endpoint config
    this.endpointConfig.addDependency(this.sageMakerModel);

    // Create SageMaker Endpoint
    this.endpoint = new sagemaker.CfnEndpoint(this, 'SageMakerEndpoint', {
      endpointName: `${resourcePrefix}-endpoint-${uniqueSuffix}`,
      endpointConfigName: this.endpointConfig.endpointConfigName!,
      tags: [
        {
          key: 'Project',
          value: 'ML-Model-Endpoints',
        },
        {
          key: 'Environment',
          value: 'Development',
        },
      ],
    });

    // Add dependency to ensure endpoint config is created before endpoint
    this.endpoint.addDependency(this.endpointConfig);

    // Configure Auto Scaling for the endpoint
    const scalableTarget = new applicationautoscaling.ScalableTarget(this, 'EndpointScalableTarget', {
      serviceNamespace: applicationautoscaling.ServiceNamespace.SAGEMAKER,
      resourceId: `endpoint/${this.endpoint.endpointName}/variant/primary`,
      scalableDimension: 'sagemaker:variant:DesiredInstanceCount',
      minCapacity: minCapacity,
      maxCapacity: maxCapacity,
    });

    // Add dependency to ensure endpoint is created before scaling target
    scalableTarget.node.addDependency(this.endpoint);

    // Create scaling policy based on invocations per instance
    scalableTarget.scaleToTrackMetric('InvocationsPerInstanceScaling', {
      targetValue: targetInvocationsPerInstance,
      predefinedMetric: applicationautoscaling.PredefinedMetric.SAGEMAKER_VARIANT_INVOCATIONS_PER_INSTANCE,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(1),
    });

    // Create CloudWatch Dashboard for monitoring
    this.dashboard = new cloudwatch.Dashboard(this, 'SageMakerDashboard', {
      dashboardName: `${resourcePrefix}-monitoring-${uniqueSuffix}`,
    });

    // Add widgets to the dashboard
    const invocationsMetric = new cloudwatch.Metric({
      namespace: 'AWS/SageMaker',
      metricName: 'Invocations',
      dimensionsMap: {
        EndpointName: this.endpoint.endpointName!,
        VariantName: 'primary',
      },
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const latencyMetric = new cloudwatch.Metric({
      namespace: 'AWS/SageMaker',
      metricName: 'ModelLatency',
      dimensionsMap: {
        EndpointName: this.endpoint.endpointName!,
        VariantName: 'primary',
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    const errorsMetric = new cloudwatch.Metric({
      namespace: 'AWS/SageMaker',
      metricName: 'Invocation4XXErrors',
      dimensionsMap: {
        EndpointName: this.endpoint.endpointName!,
        VariantName: 'primary',
      },
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const instanceCountMetric = new cloudwatch.Metric({
      namespace: 'AWS/SageMaker',
      metricName: 'CPUUtilization',
      dimensionsMap: {
        EndpointName: this.endpoint.endpointName!,
        VariantName: 'primary',
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    // Add widgets to dashboard
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Endpoint Invocations',
        left: [invocationsMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Model Latency (ms)',
        left: [latencyMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Invocation Errors',
        left: [errorsMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'CPU Utilization',
        left: [instanceCountMetric],
        width: 12,
        height: 6,
      })
    );

    // Create CloudWatch Alarms for monitoring
    new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `${resourcePrefix}-high-error-rate-${uniqueSuffix}`,
      alarmDescription: 'Alarm when endpoint error rate is too high',
      metric: errorsMetric,
      threshold: 10,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      alarmName: `${resourcePrefix}-high-latency-${uniqueSuffix}`,
      alarmDescription: 'Alarm when endpoint latency is too high',
      metric: latencyMetric,
      threshold: 10000, // 10 seconds in milliseconds
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Output important information
    new cdk.CfnOutput(this, 'ModelBucketName', {
      value: this.modelBucket.bucketName,
      description: 'S3 bucket for storing model artifacts',
      exportName: `${this.stackName}-ModelBucket`,
    });

    new cdk.CfnOutput(this, 'ECRRepositoryURI', {
      value: this.ecrRepository.repositoryUri,
      description: 'ECR repository URI for inference containers',
      exportName: `${this.stackName}-ECRRepository`,
    });

    new cdk.CfnOutput(this, 'SageMakerRoleArn', {
      value: this.sageMakerRole.roleArn,
      description: 'ARN of the SageMaker execution role',
      exportName: `${this.stackName}-SageMakerRole`,
    });

    new cdk.CfnOutput(this, 'EndpointName', {
      value: this.endpoint.endpointName!,
      description: 'Name of the SageMaker endpoint for model inference',
      exportName: `${this.stackName}-EndpointName`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for monitoring',
    });

    new cdk.CfnOutput(this, 'SampleInvocationCommand', {
      value: `aws sagemaker-runtime invoke-endpoint --endpoint-name ${this.endpoint.endpointName} --content-type application/json --body '{"instances": [[5.1, 3.5, 1.4, 0.2]]}' --region ${this.region} output.json`,
      description: 'Sample command to invoke the endpoint',
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the main stack
new SageMakerMLEndpointsStack(app, 'SageMakerMLEndpointsStack', {
  description: 'Deploy machine learning models with Amazon SageMaker endpoints including auto-scaling and monitoring',
  
  // Stack configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },

  // Customizable properties - can be overridden via CDK context
  resourcePrefix: app.node.tryGetContext('resourcePrefix') || 'ml-endpoints',
  instanceType: app.node.tryGetContext('instanceType') || 'ml.t2.medium',
  initialInstanceCount: app.node.tryGetContext('initialInstanceCount') || 1,
  minCapacity: app.node.tryGetContext('minCapacity') || 1,
  maxCapacity: app.node.tryGetContext('maxCapacity') || 5,
  targetInvocationsPerInstance: app.node.tryGetContext('targetInvocationsPerInstance') || 70.0,
  enableDetailedMonitoring: app.node.tryGetContext('enableDetailedMonitoring') !== 'false',

  // Tagging strategy
  tags: {
    Project: 'ML-Model-Endpoints',
    Environment: app.node.tryGetContext('environment') || 'Development',
    ManagedBy: 'AWS-CDK',
    Owner: app.node.tryGetContext('owner') || 'DataScience-Team',
  },
});