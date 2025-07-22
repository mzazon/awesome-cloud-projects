import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { DataVisualizationPipelineStack } from '../lib/data-visualization-pipeline-stack';

describe('DataVisualizationPipelineStack', () => {
  test('creates all required S3 buckets', () => {
    const app = new cdk.App();
    const stack = new DataVisualizationPipelineStack(app, 'TestStack', {
      projectName: 'test',
      environment: 'test',
    });

    const template = Template.fromStack(stack);

    // Should create 3 S3 buckets (raw data, processed data, athena results)
    template.resourceCountIs('AWS::S3::Bucket', 3);
  });

  test('creates Glue database and crawlers', () => {
    const app = new cdk.App();
    const stack = new DataVisualizationPipelineStack(app, 'TestStack', {
      projectName: 'test',
      environment: 'test',
    });

    const template = Template.fromStack(stack);

    // Should create 1 Glue database
    template.resourceCountIs('AWS::Glue::Database', 1);
    
    // Should create 2 Glue crawlers (raw and processed data)
    template.resourceCountIs('AWS::Glue::Crawler', 2);
    
    // Should create 1 Glue ETL job
    template.resourceCountIs('AWS::Glue::Job', 1);
  });

  test('creates Athena workgroup', () => {
    const app = new cdk.App();
    const stack = new DataVisualizationPipelineStack(app, 'TestStack', {
      projectName: 'test',
      environment: 'test',
    });

    const template = Template.fromStack(stack);

    // Should create 1 Athena workgroup
    template.resourceCountIs('AWS::Athena::WorkGroup', 1);
  });

  test('creates Lambda automation function', () => {
    const app = new cdk.App();
    const stack = new DataVisualizationPipelineStack(app, 'TestStack', {
      projectName: 'test',
      environment: 'test',
    });

    const template = Template.fromStack(stack);

    // Should create 1 Lambda function
    template.resourceCountIs('AWS::Lambda::Function', 1);
  });

  test('creates IAM role for Glue with correct policies', () => {
    const app = new cdk.App();
    const stack = new DataVisualizationPipelineStack(app, 'TestStack', {
      projectName: 'test',
      environment: 'test',
    });

    const template = Template.fromStack(stack);

    // Should create IAM role for Glue
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'glue.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
      },
    });
  });

  test('S3 buckets have proper security configurations', () => {
    const app = new cdk.App();
    const stack = new DataVisualizationPipelineStack(app, 'TestStack', {
      projectName: 'test',
      environment: 'test',
    });

    const template = Template.fromStack(stack);

    // All S3 buckets should block public access
    template.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });

  test('generates all required outputs', () => {
    const app = new cdk.App();
    const stack = new DataVisualizationPipelineStack(app, 'TestStack', {
      projectName: 'test',
      environment: 'test',
    });

    const template = Template.fromStack(stack);

    // Should have outputs for key resources
    template.hasOutput('RawDataBucketName', {});
    template.hasOutput('ProcessedDataBucketName', {});
    template.hasOutput('AthenaResultsBucketName', {});
    template.hasOutput('GlueDatabaseName', {});
    template.hasOutput('AthenaWorkgroupName', {});
    template.hasOutput('ETLJobName', {});
    template.hasOutput('AutomationFunctionName', {});
    template.hasOutput('QuickSightInstructions', {});
  });
});