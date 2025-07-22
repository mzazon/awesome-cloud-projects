import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Construct } from 'constructs';

export interface EdgeAiInferenceStackProps extends cdk.StackProps {
  projectName: string;
  environment: string;
}

/**
 * CDK Stack for Edge AI Inference with SageMaker and IoT Greengrass
 * 
 * This stack creates all the necessary infrastructure for deploying
 * machine learning models to edge devices using IoT Greengrass v2
 * with centralized monitoring through EventBridge.
 */
export class EdgeAiInferenceStack extends cdk.Stack {
  public readonly modelBucket: s3.Bucket;
  public readonly eventBus: events.EventBus;
  public readonly greengrassTokenExchangeRole: iam.Role;
  public readonly greengrassDeviceRole: iam.Role;
  public readonly iotRoleAlias: iot.CfnRoleAlias;

  constructor(scope: Construct, id: string, props: EdgeAiInferenceStackProps) {
    super(scope, id, props);

    const { projectName, environment } = props;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // ========================================================================
    // S3 Bucket for Model Storage
    // ========================================================================
    
    this.modelBucket = new s3.Bucket(this, 'ModelBucket', {
      bucketName: `${projectName}-edge-models-${uniqueSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
        {
          id: 'CleanupIncompleteUploads',
          enabled: true,
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // ========================================================================
    // IAM Roles for IoT Greengrass
    // ========================================================================

    // Token Exchange Role for Greengrass Core devices
    this.greengrassTokenExchangeRole = new iam.Role(this, 'GreengrassTokenExchangeRole', {
      roleName: `${projectName}-GreengrassV2TokenExchangeRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('credentials.iot.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('GreengrassV2TokenExchangeRoleAccess'),
      ],
      description: 'Role for IoT Greengrass Token Exchange Service',
    });

    // Device Role for Greengrass components
    this.greengrassDeviceRole = new iam.Role(this, 'GreengrassDeviceRole', {
      roleName: `${projectName}-GreengrassDeviceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('greengrass.amazonaws.com'),
      description: 'Role for Greengrass components to access AWS services',
    });

    // Policy for device role to access S3 models
    const s3ModelAccessPolicy = new iam.Policy(this, 'S3ModelAccessPolicy', {
      policyName: `${projectName}-S3ModelAccess-${uniqueSuffix}`,
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:ListBucket',
          ],
          resources: [
            this.modelBucket.bucketArn,
            `${this.modelBucket.bucketArn}/*`,
          ],
        }),
      ],
    });

    this.greengrassDeviceRole.attachInlinePolicy(s3ModelAccessPolicy);

    // ========================================================================
    // EventBridge for Centralized Monitoring
    // ========================================================================

    this.eventBus = new events.EventBus(this, 'EdgeMonitoringBus', {
      eventBusName: `${projectName}-edge-monitoring-${uniqueSuffix}`,
      description: 'Event bus for edge AI inference monitoring',
    });

    // CloudWatch Log Group for EventBridge events
    const eventLogGroup = new logs.LogGroup(this, 'EdgeInferenceLogGroup', {
      logGroupName: `/aws/events/${projectName}-edge-inference`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // EventBridge Rule for inference events
    const inferenceRule = new events.Rule(this, 'InferenceMonitoringRule', {
      ruleName: `${projectName}-edge-inference-monitoring`,
      eventBus: this.eventBus,
      eventPattern: {
        source: ['edge.ai.inference'],
        detailType: [
          'InferenceCompleted',
          'InferenceError',
          'ModelLoadError',
        ],
      },
      description: 'Route edge inference events to CloudWatch Logs',
    });

    // Add CloudWatch Logs as target
    inferenceRule.addTarget(new targets.CloudWatchLogGroup(eventLogGroup));

    // Policy for EventBridge access from edge devices
    const eventBridgeAccessPolicy = new iam.Policy(this, 'EventBridgeAccessPolicy', {
      policyName: `${projectName}-EventBridgeAccess-${uniqueSuffix}`,
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'events:PutEvents',
          ],
          resources: [this.eventBus.eventBusArn],
        }),
      ],
    });

    this.greengrassDeviceRole.attachInlinePolicy(eventBridgeAccessPolicy);

    // ========================================================================
    // IoT Core Configuration
    // ========================================================================

    // IoT Role Alias for Token Exchange
    this.iotRoleAlias = new iot.CfnRoleAlias(this, 'GreengrassRoleAlias', {
      roleAlias: `${projectName}-GreengrassV2TokenExchangeRoleAlias-${uniqueSuffix}`,
      roleArn: this.greengrassTokenExchangeRole.roleArn,
      credentialDurationSeconds: 3600, // 1 hour
    });

    // IoT Policy for Greengrass devices
    const greengrassIotPolicy = new iot.CfnPolicy(this, 'GreengrassIoTPolicy', {
      policyName: `${projectName}-GreengrassV2IoTThingPolicy-${uniqueSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              'iot:Connect',
              'iot:Publish',
              'iot:Subscribe',
              'iot:Receive',
              'greengrass:*',
            ],
            Resource: '*',
          },
        ],
      },
    });

    // ========================================================================
    // Greengrass Components Creation
    // ========================================================================

    // ONNX Runtime Component
    const onnxRuntimeComponent = new iot.CfnGreengrassComponentVersion(this, 'OnnxRuntimeComponent', {
      componentName: `${projectName}.OnnxRuntime`,
      componentVersion: '1.0.0',
      inlineRecipe: JSON.stringify({
        RecipeFormatVersion: '2020-01-25',
        ComponentName: `${projectName}.OnnxRuntime`,
        ComponentVersion: '1.0.0',
        ComponentDescription: 'ONNX Runtime for edge inference',
        ComponentPublisher: 'EdgeAI',
        Manifests: [
          {
            Platform: {
              os: 'linux',
            },
            Lifecycle: {
              Install: {
                Script: 'pip3 install onnxruntime==1.16.0 numpy==1.24.0 opencv-python-headless==4.8.0',
                Timeout: 300,
              },
            },
          },
        ],
      }),
    });

    // Model Component
    const modelComponent = new iot.CfnGreengrassComponentVersion(this, 'ModelComponent', {
      componentName: `${projectName}.DefectDetectionModel`,
      componentVersion: '1.0.0',
      inlineRecipe: JSON.stringify({
        RecipeFormatVersion: '2020-01-25',
        ComponentName: `${projectName}.DefectDetectionModel`,
        ComponentVersion: '1.0.0',
        ComponentDescription: 'Defect detection model for edge inference',
        ComponentPublisher: 'EdgeAI',
        ComponentConfiguration: {
          DefaultConfiguration: {
            ModelPath: `/greengrass/v2/work/${projectName}.DefectDetectionModel`,
            ModelS3Uri: `s3://${this.modelBucket.bucketName}/models/v1.0.0/`,
          },
        },
        Manifests: [
          {
            Platform: {
              os: 'linux',
            },
            Artifacts: [
              {
                URI: `s3://${this.modelBucket.bucketName}/models/v1.0.0/model.onnx`,
                Unarchive: 'NONE',
              },
              {
                URI: `s3://${this.modelBucket.bucketName}/models/v1.0.0/config.json`,
                Unarchive: 'NONE',
              },
            ],
            Lifecycle: {},
          },
        ],
      }),
    });

    // Inference Engine Component
    const inferenceEngineComponent = new iot.CfnGreengrassComponentVersion(this, 'InferenceEngineComponent', {
      componentName: `${projectName}.InferenceEngine`,
      componentVersion: '1.0.0',
      inlineRecipe: JSON.stringify({
        RecipeFormatVersion: '2020-01-25',
        ComponentName: `${projectName}.InferenceEngine`,
        ComponentVersion: '1.0.0',
        ComponentDescription: 'Real-time inference engine with EventBridge',
        ComponentPublisher: 'EdgeAI',
        ComponentDependencies: {
          [`${projectName}.OnnxRuntime`]: {
            VersionRequirement: '>=1.0.0 <2.0.0',
          },
          [`${projectName}.DefectDetectionModel`]: {
            VersionRequirement: '>=1.0.0 <2.0.0',
          },
        },
        ComponentConfiguration: {
          DefaultConfiguration: {
            EventBusName: this.eventBus.eventBusName,
            InferenceInterval: 10,
            ConfidenceThreshold: 0.8,
          },
        },
        Manifests: [
          {
            Platform: {
              os: 'linux',
            },
            Lifecycle: {
              Run: {
                Script: 'python3 {artifacts:path}/inference_app.py',
                RequiresPrivilege: false,
              },
            },
          },
        ],
      }),
    });

    // ========================================================================
    // CloudWatch Dashboard (Optional)
    // ========================================================================

    // Note: CloudWatch Dashboard creation would require additional imports
    // and is optional for this implementation

    // ========================================================================
    // Outputs
    // ========================================================================

    new cdk.CfnOutput(this, 'ModelBucketName', {
      value: this.modelBucket.bucketName,
      description: 'S3 bucket name for storing ML models',
      exportName: `${id}-ModelBucketName`,
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: this.eventBus.eventBusName,
      description: 'EventBridge bus name for monitoring',
      exportName: `${id}-EventBusName`,
    });

    new cdk.CfnOutput(this, 'TokenExchangeRoleArn', {
      value: this.greengrassTokenExchangeRole.roleArn,
      description: 'IAM role ARN for Greengrass Token Exchange',
      exportName: `${id}-TokenExchangeRoleArn`,
    });

    new cdk.CfnOutput(this, 'DeviceRoleArn', {
      value: this.greengrassDeviceRole.roleArn,
      description: 'IAM role ARN for Greengrass devices',
      exportName: `${id}-DeviceRoleArn`,
    });

    new cdk.CfnOutput(this, 'IoTRoleAliasName', {
      value: this.iotRoleAlias.roleAlias,
      description: 'IoT Role Alias name for device authentication',
      exportName: `${id}-IoTRoleAliasName`,
    });

    new cdk.CfnOutput(this, 'IoTPolicyName', {
      value: greengrassIotPolicy.policyName!,
      description: 'IoT Policy name for Greengrass devices',
      exportName: `${id}-IoTPolicyName`,
    });

    new cdk.CfnOutput(this, 'OnnxRuntimeComponentName', {
      value: onnxRuntimeComponent.componentName!,
      description: 'ONNX Runtime Greengrass component name',
      exportName: `${id}-OnnxRuntimeComponentName`,
    });

    new cdk.CfnOutput(this, 'ModelComponentName', {
      value: modelComponent.componentName!,
      description: 'Model Greengrass component name',
      exportName: `${id}-ModelComponentName`,
    });

    new cdk.CfnOutput(this, 'InferenceEngineComponentName', {
      value: inferenceEngineComponent.componentName!,
      description: 'Inference Engine Greengrass component name',
      exportName: `${id}-InferenceEngineComponentName`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: eventLogGroup.logGroupName,
      description: 'CloudWatch Log Group for edge inference events',
      exportName: `${id}-LogGroupName`,
    });

    // Output for manual device setup
    new cdk.CfnOutput(this, 'DeviceSetupInstructions', {
      value: [
        'To setup your edge device:',
        '1. Install AWS IoT Greengrass Core v2',
        '2. Create IoT Thing and certificates',
        '3. Attach the IoT policy to your certificates',
        `4. Use role alias: ${this.iotRoleAlias.roleAlias}`,
        '5. Deploy components using AWS CLI or console',
      ].join(' | '),
      description: 'Instructions for setting up edge devices',
    });
  }
}