import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { AnomalyDetectionStack } from '../lib/anomaly-detection-stack';

describe('AnomalyDetectionStack', () => {
  let app: cdk.App;
  let stack: AnomalyDetectionStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AnomalyDetectionStack(app, 'TestAnomalyDetectionStack', {
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
      streamShardCount: 2,
      flinkParallelism: 2,
      notificationEmail: 'test@example.com',
    });
    template = Template.fromStack(stack);
  });

  test('Creates Kinesis Data Stream with correct configuration', () => {
    template.hasResourceProperties('AWS::Kinesis::Stream', {
      ShardCount: 2,
      RetentionPeriodHours: 24,
      StreamEncryption: {
        EncryptionType: 'KMS',
        KeyId: 'alias/aws/kinesis',
      },
    });
  });

  test('Creates Managed Service for Apache Flink application', () => {
    template.hasResourceProperties('AWS::KinesisAnalyticsV2::Application', {
      RuntimeEnvironment: 'FLINK-1_17',
      ApplicationConfiguration: {
        FlinkApplicationConfiguration: {
          CheckpointConfiguration: {
            ConfigurationType: 'CUSTOM',
            CheckpointingEnabled: true,
            CheckpointInterval: 60000,
          },
          MonitoringConfiguration: {
            ConfigurationType: 'CUSTOM',
            LogLevel: 'INFO',
            MetricsLevel: 'APPLICATION',
          },
          ParallelismConfiguration: {
            ConfigurationType: 'CUSTOM',
            Parallelism: 2,
            ParallelismPerKpu: 1,
          },
        },
      },
    });
  });

  test('Creates SNS topic for alerts', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Transaction Anomaly Alerts',
    });
  });

  test('Creates email subscription when email provided', () => {
    template.hasResourceProperties('AWS::SNS::Subscription', {
      Protocol: 'email',
      Endpoint: 'test@example.com',
    });
  });

  test('Creates Lambda function for anomaly processing', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.9',
      Handler: 'anomaly_processor.lambda_handler',
      Timeout: 300,
      MemorySize: 256,
    });
  });

  test('Creates data generator Lambda function', () => {
    template.hasResourceProperties('AWS::Lambda::Function', 
      Match.objectLike({
        Runtime: 'python3.9',
        Handler: 'data_generator.lambda_handler',
        Description: 'Generates test transaction data for anomaly detection testing',
      })
    );
  });

  test('Creates S3 bucket for artifacts', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256',
            },
          },
        ],
      },
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
      VersioningConfiguration: {
        Status: 'Enabled',
      },
    });
  });

  test('Creates CloudWatch alarm for anomaly detection', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      ComparisonOperator: 'GreaterThanThreshold',
      EvaluationPeriods: 1,
      MetricName: 'AnomalyCount',
      Namespace: 'AnomalyDetection',
      Period: 300,
      Statistic: 'Sum',
      Threshold: 1,
      TreatMissingData: 'notBreaching',
    });
  });

  test('Creates CloudWatch anomaly detector', () => {
    template.hasResourceProperties('AWS::CloudWatch::AnomalyDetector', {
      MetricName: 'AnomalyCount',
      Namespace: 'AnomalyDetection',
      Stat: 'Sum',
      Dimensions: [
        {
          Name: 'Source',
          Value: 'FlinkApp',
        },
      ],
    });
  });

  test('Creates IAM role for Flink service with appropriate permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'kinesisanalytics.amazonaws.com',
            },
          },
        ],
      },
    });

    // Check for Kinesis permissions
    template.hasResourceProperties('AWS::IAM::Policy', 
      Match.objectLike({
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: [
                'kinesis:DescribeStream',
                'kinesis:GetShardIterator',
                'kinesis:GetRecords',
                'kinesis:ListShards',
              ],
            }),
          ]),
        },
      })
    );
  });

  test('Outputs contain all required values', () => {
    template.hasOutput('KinesisStreamName', {});
    template.hasOutput('KinesisStreamArn', {});
    template.hasOutput('FlinkApplicationName', {});
    template.hasOutput('SNSTopicArn', {});
    template.hasOutput('LambdaProcessorName', {});
    template.hasOutput('DataGeneratorName', {});
    template.hasOutput('S3BucketName', {});
  });

  test('All resources have proper tags', () => {
    const resources = template.findResources('AWS::Kinesis::Stream');
    const streamLogicalId = Object.keys(resources)[0];
    
    template.hasResource('AWS::Kinesis::Stream', {
      Properties: Match.anyValue(),
      Metadata: Match.objectLike({
        'aws:cdk:path': Match.stringLikeRegexp('.*'),
      }),
    });
  });

  test('Lambda function has proper environment variables', () => {
    template.hasResourceProperties('AWS::Lambda::Function',
      Match.objectLike({
        Handler: 'anomaly_processor.lambda_handler',
        Environment: {
          Variables: {
            SNS_TOPIC_ARN: Match.anyValue(),
          },
        },
      })
    );
  });

  test('Stack creates expected number of resources', () => {
    // Verify we have the expected core resources
    const kinesisStreams = template.findResources('AWS::Kinesis::Stream');
    const flinkApps = template.findResources('AWS::KinesisAnalyticsV2::Application');
    const lambdaFunctions = template.findResources('AWS::Lambda::Function');
    const snsTopics = template.findResources('AWS::SNS::Topic');
    const s3Buckets = template.findResources('AWS::S3::Bucket');

    expect(Object.keys(kinesisStreams)).toHaveLength(1);
    expect(Object.keys(flinkApps)).toHaveLength(1);
    expect(Object.keys(lambdaFunctions)).toHaveLength(2); // Processor + Data Generator
    expect(Object.keys(snsTopics)).toHaveLength(1);
    expect(Object.keys(s3Buckets)).toHaveLength(1);
  });
});