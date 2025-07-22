import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { BatchProcessingStack } from '../lib/batch-processing-stack';

describe('BatchProcessingStack', () => {
  let app: cdk.App;
  let stack: BatchProcessingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new BatchProcessingStack(app, 'TestBatchProcessingStack', {
      stackName: 'TestBatchProcessingStack',
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  test('ECR Repository Created', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      ImageScanningConfiguration: {
        ScanOnPush: true,
      },
      LifecyclePolicy: {
        LifecyclePolicyText: expect.stringContaining('maxImageCount'),
      },
    });
  });

  test('IAM Roles Created', () => {
    // Batch Service Role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'batch.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
      },
      ManagedPolicyArns: [
        'arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole',
      ],
    });

    // ECS Instance Role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'ec2.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
      },
      ManagedPolicyArns: [
        'arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role',
      ],
    });
  });

  test('Compute Environment Created', () => {
    template.hasResourceProperties('AWS::Batch::ComputeEnvironment', {
      Type: 'MANAGED',
      State: 'ENABLED',
      ComputeResources: {
        Type: 'EC2',
        MinvCpus: 0,
        MaxvCpus: 100,
        DesiredvCpus: 0,
        BidPercentage: 50,
      },
    });
  });

  test('Job Queue Created', () => {
    template.hasResourceProperties('AWS::Batch::JobQueue', {
      State: 'ENABLED',
      Priority: 1,
    });
  });

  test('Job Definition Created', () => {
    template.hasResourceProperties('AWS::Batch::JobDefinition', {
      Type: 'container',
      ContainerProperties: {
        Vcpus: 1,
        Memory: 512,
      },
      RetryStrategy: {
        Attempts: 2,
      },
      Timeout: {
        AttemptDurationSeconds: 3600,
      },
    });
  });

  test('CloudWatch Log Group Created', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/aws/batch/job',
      RetentionInDays: 30,
    });
  });

  test('Security Group Created', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for AWS Batch compute environment',
    });
  });

  test('CloudWatch Alarms Created', () => {
    // Failed jobs alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'FailedJobs',
      Namespace: 'AWS/Batch',
      Statistic: 'Sum',
      Threshold: 1,
      ComparisonOperator: 'GreaterThanOrEqualToThreshold',
    });

    // Queue utilization alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'RunnableJobs',
      Namespace: 'AWS/Batch',
      Statistic: 'Average',
      Threshold: 10,
      ComparisonOperator: 'GreaterThanThreshold',
    });
  });

  test('Stack Outputs Created', () => {
    template.hasOutput('EcrRepositoryUri', {});
    template.hasOutput('ComputeEnvironmentName', {});
    template.hasOutput('JobQueueName', {});
    template.hasOutput('JobDefinitionArn', {});
    template.hasOutput('LogGroupName', {});
  });

  test('Resource Count is Reasonable', () => {
    // Ensure we're not creating too many resources
    const resources = template.toJSON().Resources;
    const resourceCount = Object.keys(resources).length;
    
    // Should have reasonable number of resources (adjust as needed)
    expect(resourceCount).toBeGreaterThan(10);
    expect(resourceCount).toBeLessThan(30);
  });

  test('Stack is Valid', () => {
    // This will throw if the stack has validation errors
    expect(() => {
      app.synth();
    }).not.toThrow();
  });
});