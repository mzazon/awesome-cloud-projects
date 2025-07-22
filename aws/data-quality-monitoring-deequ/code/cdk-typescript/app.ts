#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as emr from 'aws-cdk-lib/aws-emr';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as s3Deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as s3Assets from 'aws-cdk-lib/aws-s3-assets';
import { RemovalPolicy, Duration, CfnParameter, CfnOutput } from 'aws-cdk-lib';

/**
 * Properties for the DataQualityMonitoringStack
 */
export interface DataQualityMonitoringStackProps extends cdk.StackProps {
  /**
   * Email address for receiving data quality alerts
   */
  alertEmail?: string;
  
  /**
   * EMR cluster instance type
   * @default m5.xlarge
   */
  instanceType?: string;
  
  /**
   * Number of EMR cluster instances
   * @default 3
   */
  instanceCount?: number;
  
  /**
   * EMR release label
   * @default emr-6.15.0
   */
  emrReleaseLabel?: string;
  
  /**
   * Whether to terminate EMR cluster automatically
   * @default false
   */
  autoTerminate?: boolean;
}

/**
 * CDK Stack for Real-time Data Quality Monitoring with Deequ on EMR
 * 
 * This stack creates a comprehensive data quality monitoring solution that includes:
 * - S3 buckets for data storage and logs
 * - EMR cluster with Deequ for distributed data quality analysis
 * - IAM roles with least privilege access
 * - SNS topic for quality alerts
 * - CloudWatch dashboard for monitoring
 * - Bootstrap scripts and monitoring applications
 */
export class DataQualityMonitoringStack extends cdk.Stack {
  
  public readonly dataBucket: s3.Bucket;
  public readonly emrCluster: emr.CfnCluster;
  public readonly alertTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: DataQualityMonitoringStackProps = {}) {
    super(scope, id, props);

    // Parameters for customization
    const alertEmailParam = new CfnParameter(this, 'AlertEmail', {
      type: 'String',
      description: 'Email address to receive data quality alerts',
      default: props.alertEmail || '',
      constraintDescription: 'Must be a valid email address'
    });

    const instanceTypeParam = new CfnParameter(this, 'InstanceType', {
      type: 'String',
      description: 'EMR cluster instance type',
      default: props.instanceType || 'm5.xlarge',
      allowedValues: ['m5.large', 'm5.xlarge', 'm5.2xlarge', 'm5.4xlarge', 'r5.large', 'r5.xlarge', 'r5.2xlarge'],
      constraintDescription: 'Must be a valid EC2 instance type'
    });

    const instanceCountParam = new CfnParameter(this, 'InstanceCount', {
      type: 'Number',
      description: 'Number of EMR cluster instances',
      default: props.instanceCount || 3,
      minValue: 1,
      maxValue: 20,
      constraintDescription: 'Must be between 1 and 20'
    });

    // Create S3 bucket for data storage with versioning and lifecycle policies
    this.dataBucket = new s3.Bucket(this, 'DataQualityBucket', {
      bucketName: `deequ-data-quality-${this.account}-${this.region}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          noncurrentVersionExpiration: Duration.days(30),
          expiredObjectDeleteMarker: true
        },
        {
          id: 'TransitionToIA',
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

    // Create folder structure in S3 bucket
    const folders = ['raw-data/', 'quality-reports/', 'logs/', 'scripts/'];
    folders.forEach((folder, index) => {
      new s3Deploy.BucketDeployment(this, `CreateFolder${index}`, {
        sources: [s3Deploy.Source.data(folder, '')],
        destinationBucket: this.dataBucket,
        destinationKeyPrefix: folder
      });
    });

    // Create SNS topic for data quality alerts
    this.alertTopic = new sns.Topic(this, 'DataQualityAlerts', {
      displayName: 'Data Quality Monitoring Alerts',
      description: 'SNS topic for data quality monitoring alerts from Deequ'
    });

    // Add email subscription if provided
    if (alertEmailParam.valueAsString) {
      this.alertTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(alertEmailParam.valueAsString)
      );
    }

    // Get default VPC
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true
    });

    // Create EMR service role
    const emrServiceRole = new iam.Role(this, 'EMRServiceRole', {
      roleName: 'EMR-DataQuality-ServiceRole',
      assumedBy: new iam.ServicePrincipal('elasticmapreduce.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonElasticMapReduceRole')
      ]
    });

    // Create EMR EC2 instance profile
    const emrInstanceRole = new iam.Role(this, 'EMRInstanceRole', {
      roleName: 'EMR-DataQuality-InstanceRole',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonElasticMapReduceforEC2Role')
      ]
    });

    // Add additional permissions for S3, CloudWatch, and SNS
    emrInstanceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket'
      ],
      resources: [
        this.dataBucket.bucketArn,
        `${this.dataBucket.bucketArn}/*`
      ]
    }));

    emrInstanceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudwatch:PutMetricData',
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:ListMetrics'
      ],
      resources: ['*']
    }));

    emrInstanceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'sns:Publish'
      ],
      resources: [this.alertTopic.topicArn]
    }));

    const emrInstanceProfile = new iam.CfnInstanceProfile(this, 'EMRInstanceProfile', {
      roles: [emrInstanceRole.roleName],
      instanceProfileName: 'EMR-DataQuality-InstanceProfile'
    });

    // Create bootstrap script content
    const bootstrapScriptContent = `#!/bin/bash

# Download and install Deequ JAR
sudo mkdir -p /usr/lib/spark/jars
sudo wget -O /usr/lib/spark/jars/deequ-2.0.4-spark-3.4.jar \\
    https://repo1.maven.org/maven2/com/amazon/deequ/deequ/2.0.4-spark-3.4/deequ-2.0.4-spark-3.4.jar

# Install required Python packages
sudo pip3 install boto3 pyarrow pandas numpy

# Create directories for custom scripts
sudo mkdir -p /opt/deequ-scripts
sudo chmod 755 /opt/deequ-scripts

echo "Deequ installation completed successfully"`;

    // Create monitoring app content
    const monitoringAppContent = `import sys
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, lit
import boto3
import json
from datetime import datetime

# Initialize Spark session with Deequ
spark = SparkSession.builder \\
    .appName("DeeQuDataQualityMonitor") \\
    .config("spark.jars.packages", "com.amazon.deequ:deequ:2.0.4-spark-3.4") \\
    .getOrCreate()

# Import Deequ classes
from pydeequ.analyzers import *
from pydeequ.checks import *
from pydeequ.verification import *
from pydeequ.suggestions import *

def publish_metrics_to_cloudwatch(metrics, bucket_name):
    """Publish data quality metrics to CloudWatch"""
    cloudwatch = boto3.client('cloudwatch')
    
    for metric_name, metric_value in metrics.items():
        cloudwatch.put_metric_data(
            Namespace='DataQuality/Deequ',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': metric_value,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'DataSource',
                            'Value': bucket_name
                        }
                    ]
                }
            ]
        )

def send_alert_if_needed(verification_result, sns_topic_arn):
    """Send SNS alert if data quality issues are found"""
    failed_checks = []
    
    for check_result in verification_result.checkResults:
        if check_result.status != CheckStatus.Success:
            failed_checks.append({
                'check': str(check_result.check),
                'status': str(check_result.status),
                'constraint': str(check_result.constraint)
            })
    
    if failed_checks:
        sns = boto3.client('sns')
        message = {
            'timestamp': datetime.now().isoformat(),
            'alert_type': 'DATA_QUALITY_FAILURE',
            'failed_checks': failed_checks,
            'total_failed_checks': len(failed_checks)
        }
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(message, indent=2),
            Subject='Data Quality Alert - Issues Detected'
        )

def main():
    # Get parameters
    if len(sys.argv) != 4:
        print("Usage: deequ-quality-monitor.py <s3_bucket> <data_path> <sns_topic_arn>")
        sys.exit(1)
    
    s3_bucket = sys.argv[1]
    data_path = sys.argv[2]
    sns_topic_arn = sys.argv[3]
    
    # Read data
    df = spark.read.option("header", "true").option("inferSchema", "true").csv(data_path)
    
    print(f"Processing {df.count()} records from {data_path}")
    
    # Define data quality checks
    verification_result = VerificationSuite(spark) \\
        .onData(df) \\
        .addCheck(
            Check(spark, CheckLevel.Error, "Customer Data Quality Checks")
            .hasSize(lambda x: x > 0)  # Non-empty dataset
            .isComplete("customer_id")  # No null customer IDs
            .isUnique("customer_id")   # Unique customer IDs
            .isComplete("email")       # No null emails
            .containsEmail("email")    # Valid email format
            .isNonNegative("age")      # Age must be non-negative
            .isContainedIn("region", ["US", "EU", "APAC"])  # Valid regions
            .hasCompleteness("income", lambda x: x > 0.9)  # At least 90% income data
        ) \\
        .run()
    
    # Run analysis for detailed metrics
    analysis_result = AnalysisRunner(spark) \\
        .onData(df) \\
        .addAnalyzer(Size()) \\
        .addAnalyzer(Completeness("customer_id")) \\
        .addAnalyzer(Completeness("email")) \\
        .addAnalyzer(Completeness("income")) \\
        .addAnalyzer(Uniqueness("customer_id")) \\
        .addAnalyzer(Mean("age")) \\
        .addAnalyzer(StandardDeviation("age")) \\
        .addAnalyzer(CountDistinct("region")) \\
        .run()
    
    # Extract metrics
    metrics = {}
    for analyzer_name, analyzer_result in analysis_result.analyzerContext.metricMap.items():
        if analyzer_result.value.isSuccess():
            metric_name = str(analyzer_name).replace(":", "_").replace("(", "_").replace(")", "_")
            metrics[metric_name] = analyzer_result.value.get()
    
    # Publish metrics to CloudWatch
    publish_metrics_to_cloudwatch(metrics, s3_bucket)
    
    # Send alerts if needed
    send_alert_if_needed(verification_result, sns_topic_arn)
    
    # Save detailed results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Save verification results
    verification_df = VerificationResult.checkResultsAsDataFrame(spark, verification_result)
    verification_df.write.mode("overwrite").json(f"s3://{s3_bucket}/quality-reports/verification_{timestamp}")
    
    # Save analysis results
    analysis_df = AnalysisResult.successMetricsAsDataFrame(spark, analysis_result)
    analysis_df.write.mode("overwrite").json(f"s3://{s3_bucket}/quality-reports/analysis_{timestamp}")
    
    print("✅ Data quality monitoring completed successfully")
    print(f"Metrics published to CloudWatch namespace: DataQuality/Deequ")
    print(f"Reports saved to: s3://{s3_bucket}/quality-reports/")
    
    # Print summary
    print("\\n=== VERIFICATION RESULTS ===")
    verification_df.show(truncate=False)
    
    print("\\n=== ANALYSIS RESULTS ===")
    analysis_df.show(truncate=False)

if __name__ == "__main__":
    main()`;

    // Deploy bootstrap script
    new s3Deploy.BucketDeployment(this, 'DeployBootstrapScript', {
      sources: [s3Deploy.Source.data('install-deequ.sh', bootstrapScriptContent)],
      destinationBucket: this.dataBucket,
      destinationKeyPrefix: 'scripts/'
    });

    // Deploy monitoring application
    new s3Deploy.BucketDeployment(this, 'DeployMonitoringApp', {
      sources: [s3Deploy.Source.data('deequ-quality-monitor.py', monitoringAppContent)],
      destinationBucket: this.dataBucket,
      destinationKeyPrefix: 'scripts/'
    });

    // Create EMR cluster configuration
    const emrConfigurations = [
      {
        classification: 'spark-defaults',
        properties: {
          'spark.sql.adaptive.enabled': 'true',
          'spark.sql.adaptive.coalescePartitions.enabled': 'true',
          'spark.serializer': 'org.apache.spark.serializer.KryoSerializer',
          'spark.sql.adaptive.skewJoin.enabled': 'true',
          'spark.sql.adaptive.localShuffleReader.enabled': 'true'
        }
      },
      {
        classification: 'spark-env',
        configurations: [
          {
            classification: 'export',
            properties: {
              'PYSPARK_PYTHON': '/usr/bin/python3',
              'PYSPARK_DRIVER_PYTHON': '/usr/bin/python3'
            }
          }
        ]
      }
    ];

    // Create EMR cluster
    this.emrCluster = new emr.CfnCluster(this, 'DeeQuEMRCluster', {
      name: 'deequ-data-quality-monitoring',
      releaseLabel: props.emrReleaseLabel || 'emr-6.15.0',
      applications: [
        { name: 'Spark' },
        { name: 'Hadoop' }
      ],
      serviceRole: emrServiceRole.roleArn,
      jobFlowRole: emrInstanceProfile.ref,
      logUri: `s3://${this.dataBucket.bucketName}/logs/`,
      configurations: emrConfigurations,
      bootstrapActions: [
        {
          name: 'Install Deequ and Dependencies',
          scriptBootstrapAction: {
            path: `s3://${this.dataBucket.bucketName}/scripts/install-deequ.sh`
          }
        }
      ],
      instances: {
        masterInstanceGroup: {
          instanceCount: 1,
          instanceType: instanceTypeParam.valueAsString,
          market: 'ON_DEMAND',
          name: 'Master'
        },
        coreInstanceGroup: {
          instanceCount: instanceCountParam.valueAsNumber - 1,
          instanceType: instanceTypeParam.valueAsString,
          market: 'ON_DEMAND',
          name: 'Core'
        },
        ec2SubnetId: vpc.publicSubnets[0].subnetId,
        keepJobFlowAliveWhenNoSteps: !props.autoTerminate,
        terminationProtected: false
      },
      tags: [
        {
          key: 'Name',
          value: 'Deequ Data Quality Monitoring Cluster'
        },
        {
          key: 'Purpose',
          value: 'DataQualityMonitoring'
        },
        {
          key: 'Environment',
          value: 'Development'
        }
      ]
    });

    // Create CloudWatch dashboard for monitoring
    this.dashboard = new cloudwatch.Dashboard(this, 'DataQualityDashboard', {
      dashboardName: 'DeeQuDataQualityMonitoring',
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Data Quality Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'DataQuality/Deequ',
                metricName: 'Size',
                dimensionsMap: {
                  DataSource: this.dataBucket.bucketName
                },
                statistic: 'Average'
              }),
              new cloudwatch.Metric({
                namespace: 'DataQuality/Deequ',
                metricName: 'Completeness_customer_id_',
                dimensionsMap: {
                  DataSource: this.dataBucket.bucketName
                },
                statistic: 'Average'
              }),
              new cloudwatch.Metric({
                namespace: 'DataQuality/Deequ',
                metricName: 'Completeness_email_',
                dimensionsMap: {
                  DataSource: this.dataBucket.bucketName
                },
                statistic: 'Average'
              }),
              new cloudwatch.Metric({
                namespace: 'DataQuality/Deequ',
                metricName: 'Completeness_income_',
                dimensionsMap: {
                  DataSource: this.dataBucket.bucketName
                },
                statistic: 'Average'
              })
            ],
            width: 12,
            height: 6
          }),
          new cloudwatch.GraphWidget({
            title: 'Data Distribution Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'DataQuality/Deequ',
                metricName: 'Uniqueness_customer_id_',
                dimensionsMap: {
                  DataSource: this.dataBucket.bucketName
                },
                statistic: 'Average'
              }),
              new cloudwatch.Metric({
                namespace: 'DataQuality/Deequ',
                metricName: 'Mean_age_',
                dimensionsMap: {
                  DataSource: this.dataBucket.bucketName
                },
                statistic: 'Average'
              }),
              new cloudwatch.Metric({
                namespace: 'DataQuality/Deequ',
                metricName: 'StandardDeviation_age_',
                dimensionsMap: {
                  DataSource: this.dataBucket.bucketName
                },
                statistic: 'Average'
              })
            ],
            width: 12,
            height: 6
          })
        ]
      ]
    });

    // Create CloudWatch alarms for critical metrics
    const lowCompletenessAlarm = new cloudwatch.Alarm(this, 'LowCompletenessAlarm', {
      alarmDescription: 'Data completeness below threshold',
      metric: new cloudwatch.Metric({
        namespace: 'DataQuality/Deequ',
        metricName: 'Completeness_customer_id_',
        dimensionsMap: {
          DataSource: this.dataBucket.bucketName
        },
        statistic: 'Average'
      }),
      threshold: 0.95,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2
    });

    lowCompletenessAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));

    // Create outputs for important resources
    new CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'Name of the S3 bucket for data storage'
    });

    new CfnOutput(this, 'EMRClusterId', {
      value: this.emrCluster.ref,
      description: 'ID of the EMR cluster'
    });

    new CfnOutput(this, 'SNSTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'ARN of the SNS topic for alerts'
    });

    new CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard'
    });

    new CfnOutput(this, 'MonitoringJobCommand', {
      value: `aws emr add-steps --cluster-id ${this.emrCluster.ref} --steps '[{"Name":"DeeQuDataQualityMonitoring","ActionOnFailure":"CONTINUE","HadoopJarStep":{"Jar":"command-runner.jar","Args":["spark-submit","--deploy-mode","cluster","--master","yarn","s3://${this.dataBucket.bucketName}/scripts/deequ-quality-monitor.py","${this.dataBucket.bucketName}","s3://${this.dataBucket.bucketName}/raw-data/sample_customer_data.csv","${this.alertTopic.topicArn}"]}}]'`,
      description: 'AWS CLI command to submit monitoring job to EMR'
    });
  }
}

// CDK App
const app = new cdk.App();

// Get context values or use defaults
const alertEmail = app.node.tryGetContext('alertEmail');
const instanceType = app.node.tryGetContext('instanceType') || 'm5.xlarge';
const instanceCount = app.node.tryGetContext('instanceCount') || 3;
const autoTerminate = app.node.tryGetContext('autoTerminate') || false;

new DataQualityMonitoringStack(app, 'DataQualityMonitoringStack', {
  description: 'Real-time Data Quality Monitoring with Deequ on EMR',
  alertEmail,
  instanceType,
  instanceCount,
  autoTerminate,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'DataQualityMonitoring',
    Technology: 'Deequ',
    Platform: 'EMR'
  }
});

app.synth();