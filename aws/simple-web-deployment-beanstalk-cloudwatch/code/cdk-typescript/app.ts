#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as elasticbeanstalk from 'aws-cdk-lib/aws-elasticbeanstalk';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import * as path from 'path';

/**
 * Properties for the SimpleWebDeploymentStack
 */
export interface SimpleWebDeploymentStackProps extends cdk.StackProps {
  /**
   * The name of the Elastic Beanstalk application
   * @default 'simple-web-app'
   */
  readonly applicationName?: string;

  /**
   * The name of the Elastic Beanstalk environment
   * @default 'simple-web-env'
   */
  readonly environmentName?: string;

  /**
   * The EC2 instance type for the Elastic Beanstalk environment
   * @default 't3.micro'
   */
  readonly instanceType?: string;

  /**
   * CloudWatch log retention period in days
   * @default 7
   */
  readonly logRetentionDays?: number;

  /**
   * Whether to enable enhanced health reporting
   * @default true
   */
  readonly enhancedHealthReporting?: boolean;
}

/**
 * CDK Stack for Simple Web Application Deployment with Elastic Beanstalk and CloudWatch
 * 
 * This stack creates:
 * - S3 bucket for application source code
 * - Elastic Beanstalk application and environment
 * - IAM roles and policies for Elastic Beanstalk
 * - CloudWatch alarms for monitoring
 * - CloudWatch log groups for application logs
 */
export class SimpleWebDeploymentStack extends cdk.Stack {
  /**
   * The Elastic Beanstalk application
   */
  public readonly application: elasticbeanstalk.CfnApplication;

  /**
   * The Elastic Beanstalk environment
   */
  public readonly environment: elasticbeanstalk.CfnEnvironment;

  /**
   * The S3 bucket containing the application source code
   */
  public readonly sourceBucket: s3.Bucket;

  /**
   * The application URL
   */
  public readonly applicationUrl: string;

  constructor(scope: Construct, id: string, props: SimpleWebDeploymentStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const applicationName = props.applicationName || 'simple-web-app';
    const environmentName = props.environmentName || 'simple-web-env';
    const instanceType = props.instanceType || 't3.micro';
    const logRetentionDays = props.logRetentionDays || 7;
    const enhancedHealthReporting = props.enhancedHealthReporting ?? true;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();
    const uniqueApplicationName = `${applicationName}-${uniqueSuffix}`;
    const uniqueEnvironmentName = `${environmentName}-${uniqueSuffix}`;

    // Create S3 bucket for application source code
    this.sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `eb-source-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
    });

    // Create sample application files and deploy to S3
    this.createSampleApplication();

    // Create IAM role for Elastic Beanstalk service
    const serviceRole = new iam.Role(this, 'ElasticBeanstalkServiceRole', {
      assumedBy: new iam.ServicePrincipal('elasticbeanstalk.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSElasticBeanstalkEnhancedHealth'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy'),
      ],
    });

    // Create IAM role for EC2 instances
    const instanceRole = new iam.Role(this, 'ElasticBeanstalkInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSElasticBeanstalkWebTier'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSElasticBeanstalkMulticontainerDocker'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSElasticBeanstalkWorkerTier'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // Create instance profile
    const instanceProfile = new iam.CfnInstanceProfile(this, 'ElasticBeanstalkInstanceProfile', {
      roles: [instanceRole.roleName],
      instanceProfileName: `eb-instance-profile-${uniqueSuffix}`,
    });

    // Create CloudWatch log group for application logs
    const logGroup = new logs.LogGroup(this, 'ApplicationLogGroup', {
      logGroupName: `/aws/elasticbeanstalk/${uniqueEnvironmentName}/var/log/eb-engine.log`,
      retention: logRetentionDays as logs.RetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Elastic Beanstalk application
    this.application = new elasticbeanstalk.CfnApplication(this, 'Application', {
      applicationName: uniqueApplicationName,
      description: 'Simple web application for learning deployment with CloudWatch monitoring',
    });

    // Create application version
    const applicationVersion = new elasticbeanstalk.CfnApplicationVersion(this, 'ApplicationVersion', {
      applicationName: this.application.ref,
      description: 'Initial deployment version',
      sourceBundle: {
        s3Bucket: this.sourceBucket.bucketName,
        s3Key: 'application-source.zip',
      },
    });

    // Define configuration options for the environment
    const configurationOptions: elasticbeanstalk.CfnEnvironment.OptionSettingProperty[] = [
      // Instance configuration
      {
        namespace: 'aws:autoscaling:launchconfiguration',
        optionName: 'InstanceType',
        value: instanceType,
      },
      {
        namespace: 'aws:autoscaling:launchconfiguration',
        optionName: 'IamInstanceProfile',
        value: instanceProfile.ref,
      },
      // CloudWatch Logs configuration
      {
        namespace: 'aws:elasticbeanstalk:cloudwatch:logs',
        optionName: 'StreamLogs',
        value: 'true',
      },
      {
        namespace: 'aws:elasticbeanstalk:cloudwatch:logs',
        optionName: 'DeleteOnTerminate',
        value: 'false',
      },
      {
        namespace: 'aws:elasticbeanstalk:cloudwatch:logs',
        optionName: 'RetentionInDays',
        value: logRetentionDays.toString(),
      },
      // Health monitoring configuration
      {
        namespace: 'aws:elasticbeanstalk:cloudwatch:logs:health',
        optionName: 'HealthStreamingEnabled',
        value: 'true',
      },
      {
        namespace: 'aws:elasticbeanstalk:cloudwatch:logs:health',
        optionName: 'DeleteOnTerminate',
        value: 'false',
      },
      {
        namespace: 'aws:elasticbeanstalk:cloudwatch:logs:health',
        optionName: 'RetentionInDays',
        value: logRetentionDays.toString(),
      },
      // Enhanced health reporting
      {
        namespace: 'aws:elasticbeanstalk:healthreporting:system',
        optionName: 'SystemType',
        value: enhancedHealthReporting ? 'enhanced' : 'basic',
      },
      {
        namespace: 'aws:elasticbeanstalk:healthreporting:system',
        optionName: 'EnhancedHealthAuthEnabled',
        value: enhancedHealthReporting.toString(),
      },
      // Service role
      {
        namespace: 'aws:elasticbeanstalk:environment',
        optionName: 'ServiceRole',
        value: serviceRole.roleArn,
      },
    ];

    // Create Elastic Beanstalk environment
    this.environment = new elasticbeanstalk.CfnEnvironment(this, 'Environment', {
      applicationName: this.application.ref,
      environmentName: uniqueEnvironmentName,
      solutionStackName: '64bit Amazon Linux 2023 v4.6.1 running Python 3.11',
      versionLabel: applicationVersion.ref,
      tier: {
        name: 'WebServer',
        type: 'Standard',
      },
      optionSettings: configurationOptions,
    });

    // Set dependencies
    this.environment.addDependency(applicationVersion);
    applicationVersion.addDependency(this.application);

    // Create CloudWatch alarms for monitoring
    this.createCloudWatchAlarms(uniqueEnvironmentName);

    // Store application URL for outputs
    this.applicationUrl = `http://${this.environment.attrEndpointUrl}`;

    // Create stack outputs
    this.createOutputs(uniqueApplicationName, uniqueEnvironmentName);

    // Add tags to all resources
    cdk.Tags.of(this).add('Application', 'SimpleWebDeployment');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Creates sample application files and deploys them to S3
   */
  private createSampleApplication(): void {
    // Deploy sample application files to S3
    // Note: In a real scenario, you would have actual application files
    // For this CDK example, we'll create a deployment that assumes the files exist
    new s3deploy.BucketDeployment(this, 'ApplicationDeployment', {
      sources: [
        s3deploy.Source.data('application.py', this.getPythonApplicationCode()),
        s3deploy.Source.data('requirements.txt', this.getRequirementsContent()),
        s3deploy.Source.data('templates/index.html', this.getHtmlTemplate()),
        s3deploy.Source.data('.ebextensions/cloudwatch-logs.config', this.getEbExtensionsConfig()),
      ],
      destinationBucket: this.sourceBucket,
      destinationKeyPrefix: '',
      extract: false,
      prune: false,
    });
  }

  /**
   * Returns the Python Flask application code
   */
  private getPythonApplicationCode(): string {
    return `import flask
import logging
from datetime import datetime

# Create Flask application instance
application = flask.Flask(__name__)

# Configure logging for CloudWatch
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@application.route('/')
def hello():
    logger.info("Home page accessed")
    return flask.render_template('index.html')

@application.route('/health')
def health():
    logger.info("Health check accessed")
    return {'status': 'healthy', 'timestamp': datetime.now().isoformat()}

@application.route('/api/info')
def info():
    logger.info("Info API accessed")
    return {
        'application': 'Simple Web App',
        'version': '1.0',
        'environment': 'production'
    }

if __name__ == '__main__':
    application.run(debug=True)
`;
  }

  /**
   * Returns the requirements.txt content
   */
  private getRequirementsContent(): string {
    return `Flask==3.0.3
Werkzeug==3.0.3
`;
  }

  /**
   * Returns the HTML template content
   */
  private getHtmlTemplate(): string {
    return `<!DOCTYPE html>
<html>
<head>
    <title>Simple Web App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 600px; margin: 0 auto; }
        .status { background: #e8f5e8; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Simple Web App</h1>
        <div class="status">
            <h3>Application Status: Running</h3>
            <p>This application is deployed on AWS Elastic Beanstalk with CloudWatch monitoring enabled.</p>
            <ul>
                <li><a href="/health">Health Check</a></li>
                <li><a href="/api/info">Application Info</a></li>
            </ul>
        </div>
    </div>
</body>
</html>
`;
  }

  /**
   * Returns the Elastic Beanstalk extensions configuration
   */
  private getEbExtensionsConfig(): string {
    return `option_settings:
  aws:elasticbeanstalk:cloudwatch:logs:
    StreamLogs: true
    DeleteOnTerminate: false
    RetentionInDays: 7
  aws:elasticbeanstalk:cloudwatch:logs:health:
    HealthStreamingEnabled: true
    DeleteOnTerminate: false
    RetentionInDays: 7
  aws:elasticbeanstalk:healthreporting:system:
    SystemType: enhanced
    EnhancedHealthAuthEnabled: true
`;
  }

  /**
   * Creates CloudWatch alarms for application monitoring
   */
  private createCloudWatchAlarms(environmentName: string): void {
    // Create alarm for environment health
    new cloudwatch.Alarm(this, 'EnvironmentHealthAlarm', {
      alarmName: `${environmentName}-health-alarm`,
      alarmDescription: 'Monitor Elastic Beanstalk environment health',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ElasticBeanstalk',
        metricName: 'EnvironmentHealth',
        dimensionsMap: {
          EnvironmentName: environmentName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 15,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create alarm for 4xx application errors
    new cloudwatch.Alarm(this, 'Application4xxErrorsAlarm', {
      alarmName: `${environmentName}-4xx-errors`,
      alarmDescription: 'Monitor 4xx application errors',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ElasticBeanstalk',
        metricName: 'ApplicationRequests4xx',
        dimensionsMap: {
          EnvironmentName: environmentName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create alarm for 5xx application errors
    new cloudwatch.Alarm(this, 'Application5xxErrorsAlarm', {
      alarmName: `${environmentName}-5xx-errors`,
      alarmDescription: 'Monitor 5xx application errors',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ElasticBeanstalk',
        metricName: 'ApplicationRequests5xx',
        dimensionsMap: {
          EnvironmentName: environmentName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create alarm for application latency
    new cloudwatch.Alarm(this, 'ApplicationLatencyAlarm', {
      alarmName: `${environmentName}-latency-alarm`,
      alarmDescription: 'Monitor application response latency',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ElasticBeanstalk',
        metricName: 'ApplicationLatencyP99',
        dimensionsMap: {
          EnvironmentName: environmentName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 2000, // 2 seconds in milliseconds
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  /**
   * Creates stack outputs
   */
  private createOutputs(applicationName: string, environmentName: string): void {
    new cdk.CfnOutput(this, 'ApplicationName', {
      value: applicationName,
      description: 'Name of the Elastic Beanstalk application',
      exportName: `${this.stackName}-ApplicationName`,
    });

    new cdk.CfnOutput(this, 'EnvironmentName', {
      value: environmentName,
      description: 'Name of the Elastic Beanstalk environment',
      exportName: `${this.stackName}-EnvironmentName`,
    });

    new cdk.CfnOutput(this, 'ApplicationUrl', {
      value: this.applicationUrl,
      description: 'URL of the deployed web application',
      exportName: `${this.stackName}-ApplicationUrl`,
    });

    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'Name of the S3 bucket containing application source',
      exportName: `${this.stackName}-SourceBucketName`,
    });

    new cdk.CfnOutput(this, 'MonitoringDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:`,
      description: 'CloudWatch monitoring dashboard URL',
      exportName: `${this.stackName}-MonitoringDashboardUrl`,
    });
  }
}

/**
 * Main CDK App
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const stackName = app.node.tryGetContext('stackName') || process.env.STACK_NAME || 'SimpleWebDeploymentStack';
const applicationName = app.node.tryGetContext('applicationName') || process.env.APPLICATION_NAME;
const environmentName = app.node.tryGetContext('environmentName') || process.env.ENVIRONMENT_NAME;
const instanceType = app.node.tryGetContext('instanceType') || process.env.INSTANCE_TYPE;

// Create the stack
new SimpleWebDeploymentStack(app, stackName, {
  applicationName,
  environmentName,
  instanceType,
  description: 'Simple Web Application Deployment with Elastic Beanstalk and CloudWatch monitoring',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SimpleWebDeployment',
    Environment: 'Development',
    Owner: 'CDK',
    CostCenter: 'Development',
  },
});

// Synthesize the CDK app
app.synth();