import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as s3Notifications from 'aws-cdk-lib/aws-s3-notifications';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as guardduty from 'aws-cdk-lib/aws-guardduty';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as logsDestinations from 'aws-cdk-lib/aws-logs-destinations';
import { Construct } from 'constructs';

/**
 * Properties for the SecurityComplianceAuditingStack
 */
export interface SecurityComplianceAuditingStackProps extends cdk.StackProps {
  /**
   * Email address to receive security alerts
   * @default 'security-admin@yourcompany.com'
   */
  readonly emailForAlerts?: string;

  /**
   * Whether to create a demo VPC Lattice service network for testing
   * @default true
   */
  readonly enableVpcLatticeDemo?: boolean;
}

/**
 * CDK Stack for Security Compliance Auditing with VPC Lattice and GuardDuty
 * 
 * This stack creates:
 * - GuardDuty detector for threat detection
 * - S3 bucket for compliance reports and log storage
 * - CloudWatch log group for VPC Lattice access logs
 * - Lambda function for security log processing and analysis
 * - SNS topic for security alerts
 * - CloudWatch dashboard for monitoring
 * - VPC Lattice service network (demo configuration)
 * - Log subscription filter for real-time processing
 */
export class SecurityComplianceAuditingStack extends cdk.Stack {
  /**
   * GuardDuty detector for threat detection
   */
  public readonly guardDutyDetector: guardduty.CfnDetector;

  /**
   * S3 bucket for storing compliance reports
   */
  public readonly complianceReportsBucket: s3.Bucket;

  /**
   * Lambda function for processing security logs
   */
  public readonly securityProcessorFunction: lambda.Function;

  /**
   * SNS topic for security alerts
   */
  public readonly securityAlertsTopic: sns.Topic;

  /**
   * CloudWatch log group for VPC Lattice logs
   */
  public readonly vpcLatticeLogGroup: logs.LogGroup;

  /**
   * CloudWatch dashboard for security monitoring
   */
  public readonly securityDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: SecurityComplianceAuditingStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create GuardDuty detector
    this.guardDutyDetector = this.createGuardDutyDetector();

    // Create S3 bucket for compliance reports
    this.complianceReportsBucket = this.createComplianceReportsBucket(uniqueSuffix);

    // Create CloudWatch log group for VPC Lattice access logs
    this.vpcLatticeLogGroup = this.createVpcLatticeLogGroup();

    // Create SNS topic for security alerts
    this.securityAlertsTopic = this.createSecurityAlertsTopic(uniqueSuffix, props.emailForAlerts);

    // Create Lambda function for security processing
    this.securityProcessorFunction = this.createSecurityProcessorFunction();

    // Create log subscription filter
    this.createLogSubscriptionFilter();

    // Create CloudWatch dashboard
    this.securityDashboard = this.createSecurityDashboard();

    // Configure S3 event notifications for compliance reports
    this.configureS3Notifications();

    // Optionally create demo VPC Lattice service network
    if (props.enableVpcLatticeDemo !== false) {
      this.createDemoVpcLatticeNetwork(uniqueSuffix);
    }

    // Output important resource identifiers
    this.createOutputs();
  }

  /**
   * Creates GuardDuty detector for threat detection
   */
  private createGuardDutyDetector(): guardduty.CfnDetector {
    const detector = new guardduty.CfnDetector(this, 'GuardDutyDetector', {
      enable: true,
      findingPublishingFrequency: 'FIFTEEN_MINUTES',
      dataSources: {
        s3Logs: { enable: true },
        kubernetesAuditLogs: { enable: true },
        malwareProtection: { 
          scanEc2InstanceWithFindings: { 
            ebsVolumes: true 
          } 
        },
      },
    });

    detector.applyRemovalPolicy(cdk.RemovalPolicy.DESTROY);

    return detector;
  }

  /**
   * Creates S3 bucket for storing compliance reports with security best practices
   */
  private createComplianceReportsBucket(uniqueSuffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ComplianceReportsBucket', {
      bucketName: `security-audit-logs-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: cdk.Duration.days(90),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(60),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Note: S3 event notifications will be configured after SNS topic creation

    return bucket;
  }

  /**
   * Creates CloudWatch log group for VPC Lattice access logs
   */
  private createVpcLatticeLogGroup(): logs.LogGroup {
    const logGroup = new logs.LogGroup(this, 'VpcLatticeLogGroup', {
      logGroupName: '/aws/vpclattice/security-audit',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    return logGroup;
  }

  /**
   * Creates SNS topic for security alerts with email subscription
   */
  private createSecurityAlertsTopic(uniqueSuffix: string, email?: string): sns.Topic {
    const topic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `security-alerts-${uniqueSuffix}`,
      displayName: 'Security Compliance Alerts',
    });

    // Add email subscription if provided
    if (email) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(email));
    }

    return topic;
  }

  /**
   * Creates Lambda function for security log processing
   */
  private createSecurityProcessorFunction(): lambda.Function {
    // Create IAM role for Lambda with necessary permissions
    const lambdaRole = new iam.Role(this, 'SecurityProcessorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for Security Compliance Processor Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add specific permissions for security processing
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogStreams',
        'logs:FilterLogEvents',
      ],
      resources: ['*'],
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'guardduty:GetDetector',
        'guardduty:GetFindings',
        'guardduty:ListFindings',
      ],
      resources: ['*'],
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:ListBucket',
      ],
      resources: [
        this.complianceReportsBucket.bucketArn,
        `${this.complianceReportsBucket.bucketArn}/*`,
      ],
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['sns:Publish'],
      resources: [this.securityAlertsTopic.topicArn],
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['cloudwatch:PutMetricData'],
      resources: ['*'],
    }));

    // Create Lambda function
    const lambdaFunction = new lambda.Function(this, 'SecurityProcessorFunction', {
      functionName: 'security-compliance-processor',
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'security_processor.lambda_handler',
      code: lambda.Code.fromAsset('./lib/lambda/security-processor'),
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      role: lambdaRole,
      environment: {
        GUARDDUTY_DETECTOR_ID: this.guardDutyDetector.attrDetectorId,
        BUCKET_NAME: this.complianceReportsBucket.bucketName,
        SNS_TOPIC_ARN: this.securityAlertsTopic.topicArn,
      },
      description: 'Processes VPC Lattice access logs and correlates with GuardDuty findings',
    });

    return lambdaFunction;
  }

  /**
   * Creates CloudWatch log subscription filter for real-time processing
   */
  private createLogSubscriptionFilter(): void {
    const subscriptionFilter = new logs.SubscriptionFilter(this, 'SecurityComplianceFilter', {
      logGroup: this.vpcLatticeLogGroup,
      destination: new logsDestinations.LambdaDestination(this.securityProcessorFunction),
      filterPattern: logs.FilterPattern.allEvents(),
      filterName: 'SecurityComplianceFilter',
    });

    // Grant CloudWatch Logs permission to invoke Lambda
    this.securityProcessorFunction.addPermission('AllowCWLogsInvocation', {
      principal: new iam.ServicePrincipal('logs.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: `arn:aws:logs:${this.region}:${this.account}:log-group:${this.vpcLatticeLogGroup.logGroupName}:*`,
    });
  }

  /**
   * Creates CloudWatch dashboard for security monitoring
   */
  private createSecurityDashboard(): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'SecurityComplianceDashboard', {
      dashboardName: 'SecurityComplianceDashboard',
    });

    // VPC Lattice traffic overview widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'VPC Lattice Traffic Overview',
        left: [
          new cloudwatch.Metric({
            namespace: 'Security/VPCLattice',
            metricName: 'RequestCount',
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'Security/VPCLattice',
            metricName: 'ErrorCount',
            statistic: 'Sum',
          }),
        ],
        width: 12,
        height: 6,
      }),

      new cloudwatch.GraphWidget({
        title: 'Average Response Time',
        left: [
          new cloudwatch.Metric({
            namespace: 'Security/VPCLattice',
            metricName: 'AverageResponseTime',
            statistic: 'Average',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Lambda function metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Security Processor Lambda Metrics',
        left: [
          this.securityProcessorFunction.metricInvocations(),
          this.securityProcessorFunction.metricErrors(),
        ],
        right: [
          this.securityProcessorFunction.metricDuration(),
        ],
        width: 24,
        height: 6,
      })
    );

    // Recent security alerts log widget
    dashboard.addWidgets(
      new cloudwatch.LogQueryWidget({
        title: 'Recent Security Alerts',
        logGroups: [this.securityProcessorFunction.logGroup],
        queryLines: [
          'fields @timestamp, @message',
          'filter @message like /SECURITY_VIOLATION/',
          'sort @timestamp desc',
          'limit 20',
        ],
        width: 24,
        height: 6,
      })
    );

    return dashboard;
  }

  /**
   * Configures S3 event notifications for compliance reports
   */
  private configureS3Notifications(): void {
    // Add notification configuration for new compliance reports
    this.complianceReportsBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3Notifications.SnsDestination(this.securityAlertsTopic),
      { prefix: 'compliance-reports/' }
    );
  }

  /**
   * Creates demo VPC Lattice service network for testing
   */
  private createDemoVpcLatticeNetwork(uniqueSuffix: string): vpclattice.CfnServiceNetwork {
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'DemoServiceNetwork', {
      name: `security-demo-network-${uniqueSuffix}`,
    });

    // Configure access logging for the service network
    new vpclattice.CfnAccessLogSubscription(this, 'ServiceNetworkAccessLogs', {
      resourceIdentifier: serviceNetwork.attrId,
      destinationArn: this.vpcLatticeLogGroup.logGroupArn,
    });

    serviceNetwork.applyRemovalPolicy(cdk.RemovalPolicy.DESTROY);

    return serviceNetwork;
  }

  /**
   * Creates CloudFormation outputs for important resource identifiers
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'GuardDutyDetectorId', {
      value: this.guardDutyDetector.attrDetectorId,
      description: 'GuardDuty Detector ID for threat detection',
      exportName: `${this.stackName}-GuardDutyDetectorId`,
    });

    new cdk.CfnOutput(this, 'ComplianceReportsBucketName', {
      value: this.complianceReportsBucket.bucketName,
      description: 'S3 bucket name for compliance reports',
      exportName: `${this.stackName}-ComplianceReportsBucket`,
    });

    new cdk.CfnOutput(this, 'SecurityAlertsTopicArn', {
      value: this.securityAlertsTopic.topicArn,
      description: 'SNS topic ARN for security alerts',
      exportName: `${this.stackName}-SecurityAlertsTopic`,
    });

    new cdk.CfnOutput(this, 'SecurityProcessorFunctionName', {
      value: this.securityProcessorFunction.functionName,
      description: 'Lambda function name for security processing',
      exportName: `${this.stackName}-SecurityProcessorFunction`,
    });

    new cdk.CfnOutput(this, 'VpcLatticeLogGroupName', {
      value: this.vpcLatticeLogGroup.logGroupName,
      description: 'CloudWatch log group for VPC Lattice access logs',
      exportName: `${this.stackName}-VpcLatticeLogGroup`,
    });

    new cdk.CfnOutput(this, 'SecurityDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.securityDashboard.dashboardName}`,
      description: 'URL to security compliance dashboard',
    });
  }
}