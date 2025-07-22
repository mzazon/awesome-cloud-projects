import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as bedrock from 'aws-cdk-lib/aws-bedrock';
import * as logs from 'aws-cdk-lib/aws-logs';

export interface ContentModerationStackProps extends cdk.StackProps {
  /**
   * Email address to receive moderation notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Prefix for resource names
   */
  readonly resourcePrefix?: string;
}

export class ContentModerationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ContentModerationStackProps = {}) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'content-moderation';
    const notificationEmail = props.notificationEmail || 'admin@example.com';

    // ========================================
    // S3 Buckets for Content Storage
    // ========================================
    
    // Content upload bucket
    const contentBucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `${resourcePrefix}-content-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'delete-old-versions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    // Approved content bucket
    const approvedBucket = new s3.Bucket(this, 'ApprovedBucket', {
      bucketName: `${resourcePrefix}-approved-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'intelligent-tiering',
          transitions: [
            {
              storageClass: s3.StorageClass.INTELLIGENT_TIERING,
              transitionAfter: cdk.Duration.days(1),
            },
          ],
        },
      ],
    });

    // Rejected content bucket
    const rejectedBucket = new s3.Bucket(this, 'RejectedBucket', {
      bucketName: `${resourcePrefix}-rejected-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'delete-rejected-content',
          expiration: cdk.Duration.days(90),
        },
      ],
    });

    // ========================================
    // SNS Topic for Notifications
    // ========================================
    
    const notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${resourcePrefix}-notifications`,
      displayName: 'Content Moderation Notifications',
    });

    // Add email subscription
    notificationTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(notificationEmail)
    );

    // ========================================
    // EventBridge Custom Bus
    // ========================================
    
    const customEventBus = new events.EventBus(this, 'CustomEventBus', {
      eventBusName: `${resourcePrefix}-bus`,
      description: 'Event bus for content moderation workflows',
    });

    // ========================================
    // Bedrock Guardrails
    // ========================================
    
    const contentModerationGuardrail = new bedrock.CfnGuardrail(this, 'ContentModerationGuardrail', {
      name: 'ContentModerationGuardrail',
      description: 'Guardrail for content moderation to prevent harmful content',
      blockedInputMessaging: 'This content violates our content policy.',
      blockedOutputsMessaging: 'I cannot provide that type of content.',
      
      contentPolicyConfig: {
        filtersConfig: [
          {
            type: 'SEXUAL',
            inputStrength: 'HIGH',
            outputStrength: 'HIGH',
          },
          {
            type: 'VIOLENCE',
            inputStrength: 'HIGH',
            outputStrength: 'HIGH',
          },
          {
            type: 'HATE',
            inputStrength: 'HIGH',
            outputStrength: 'HIGH',
          },
          {
            type: 'INSULTS',
            inputStrength: 'MEDIUM',
            outputStrength: 'MEDIUM',
          },
          {
            type: 'MISCONDUCT',
            inputStrength: 'HIGH',
            outputStrength: 'HIGH',
          },
        ],
      },
      
      topicPolicyConfig: {
        topicsConfig: [
          {
            name: 'IllegalActivities',
            definition: 'Content promoting or instructing illegal activities',
            examples: ['How to make illegal substances', 'Tax evasion strategies'],
            type: 'DENY',
          },
        ],
      },
      
      sensitiveInformationPolicyConfig: {
        piiEntitiesConfig: [
          {
            type: 'EMAIL',
            action: 'ANONYMIZE',
          },
          {
            type: 'PHONE',
            action: 'ANONYMIZE',
          },
          {
            type: 'CREDIT_DEBIT_CARD_NUMBER',
            action: 'BLOCK',
          },
        ],
      },
    });

    // ========================================
    // IAM Roles and Policies
    // ========================================
    
    // Content Analysis Lambda Role
    const contentAnalysisRole = new iam.Role(this, 'ContentAnalysisRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for content analysis Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Workflow Lambda Role
    const workflowRole = new iam.Role(this, 'WorkflowRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for workflow Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Bedrock permissions for content analysis
    contentAnalysisRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'bedrock:InvokeModel',
          'bedrock:InvokeModelWithResponseStream',
        ],
        resources: [
          `arn:aws:bedrock:${this.region}::foundation-model/anthropic.*`,
        ],
      })
    );

    // S3 permissions for content analysis
    contentAnalysisRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:GetObjectVersion',
        ],
        resources: [
          contentBucket.bucketArn + '/*',
        ],
      })
    );

    // EventBridge permissions for content analysis
    contentAnalysisRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'events:PutEvents',
        ],
        resources: [
          customEventBus.eventBusArn,
        ],
      })
    );

    // S3 permissions for workflow functions
    workflowRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:CopyObject',
        ],
        resources: [
          contentBucket.bucketArn + '/*',
          approvedBucket.bucketArn + '/*',
          rejectedBucket.bucketArn + '/*',
        ],
      })
    );

    // SNS permissions for workflow functions
    workflowRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'sns:Publish',
        ],
        resources: [
          notificationTopic.topicArn,
        ],
      })
    );

    // ========================================
    // Lambda Functions
    // ========================================
    
    // Content Analysis Lambda Function
    const contentAnalysisFunction = new lambda.Function(this, 'ContentAnalysisFunction', {
      functionName: `${resourcePrefix}-content-analysis`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      role: contentAnalysisRole,
      environment: {
        EVENT_BUS_NAME: customEventBus.eventBusName,
      },
      code: lambda.Code.fromAsset('lambda-functions/content-analysis/'),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Workflow Lambda Functions
    const workflowFunctions = ['approved', 'rejected', 'review'].map(decision => 
      new lambda.Function(this, `${decision.charAt(0).toUpperCase() + decision.slice(1)}HandlerFunction`, {
        functionName: `${resourcePrefix}-${decision}-handler`,
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.lambda_handler',
        timeout: cdk.Duration.seconds(30),
        memorySize: 256,
        role: workflowRole,
        environment: {
          APPROVED_BUCKET: approvedBucket.bucketName,
          REJECTED_BUCKET: rejectedBucket.bucketName,
          SNS_TOPIC_ARN: notificationTopic.topicArn,
          WORKFLOW_TYPE: decision,
        },
        code: lambda.Code.fromAsset(`lambda-functions/${decision}-handler/`),
        logRetention: logs.RetentionDays.ONE_WEEK,
      })
    );

    // ========================================
    // S3 Event Notifications
    // ========================================
    
    // Configure S3 to trigger content analysis on .txt file uploads
    contentBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(contentAnalysisFunction),
      { suffix: '.txt' }
    );

    // ========================================
    // EventBridge Rules
    // ========================================
    
    // Create EventBridge rules for each decision type
    const decisions = ['approved', 'rejected', 'review'];
    decisions.forEach((decision, index) => {
      const rule = new events.Rule(this, `${decision.charAt(0).toUpperCase() + decision.slice(1)}ContentRule`, {
        eventBus: customEventBus,
        eventPattern: {
          source: ['content.moderation'],
          detailType: [`Content ${decision.charAt(0).toUpperCase() + decision.slice(1)}`],
        },
        description: `Route ${decision} content to appropriate handler`,
      });

      // Add Lambda target to rule
      rule.addTarget(new targets.LambdaFunction(workflowFunctions[index]));
    });

    // ========================================
    // CloudWatch Log Groups
    // ========================================
    
    // Create log groups for better organization
    new logs.LogGroup(this, 'ContentAnalysisLogGroup', {
      logGroupName: `/aws/lambda/${contentAnalysisFunction.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    workflowFunctions.forEach((func, index) => {
      new logs.LogGroup(this, `${decisions[index].charAt(0).toUpperCase() + decisions[index].slice(1)}HandlerLogGroup`, {
        logGroupName: `/aws/lambda/${func.functionName}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });
    });

    // ========================================
    // Stack Outputs
    // ========================================
    
    new cdk.CfnOutput(this, 'ContentBucketName', {
      value: contentBucket.bucketName,
      description: 'Name of the content upload bucket',
    });

    new cdk.CfnOutput(this, 'ApprovedBucketName', {
      value: approvedBucket.bucketName,
      description: 'Name of the approved content bucket',
    });

    new cdk.CfnOutput(this, 'RejectedBucketName', {
      value: rejectedBucket.bucketName,
      description: 'Name of the rejected content bucket',
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: customEventBus.eventBusName,
      description: 'Name of the custom EventBridge bus',
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'ARN of the SNS notification topic',
    });

    new cdk.CfnOutput(this, 'GuardrailId', {
      value: contentModerationGuardrail.attrGuardrailId,
      description: 'ID of the Bedrock guardrail',
    });

    new cdk.CfnOutput(this, 'ContentAnalysisFunctionName', {
      value: contentAnalysisFunction.functionName,
      description: 'Name of the content analysis Lambda function',
    });
  }
}