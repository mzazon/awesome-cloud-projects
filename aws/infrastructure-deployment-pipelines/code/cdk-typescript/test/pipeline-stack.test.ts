import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { PipelineStack } from '../lib/pipeline-stack';

describe('PipelineStack', () => {
  let app: cdk.App;
  let stack: PipelineStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new PipelineStack(app, 'TestPipelineStack', {
      repositoryName: 'test-repo',
      branchName: 'main',
      projectName: 'test-project',
    });
    template = Template.fromStack(stack);
  });

  test('should create a CodeCommit repository', () => {
    template.hasResourceProperties('AWS::CodeCommit::Repository', {
      RepositoryName: 'test-repo',
      RepositoryDescription: 'Infrastructure deployment repository with CDK code',
    });
  });

  test('should create a CodePipeline', () => {
    template.hasResourceProperties('AWS::CodePipeline::Pipeline', {
      Name: 'test-project-pipeline',
      RoleArn: {
        'Fn::GetAtt': [
          expect.stringMatching(/PipelineRole.*/),
          'Arn',
        ],
      },
    });
  });

  test('should create CodeBuild projects', () => {
    // CDK Build Project
    template.hasResourceProperties('AWS::CodeBuild::Project', {
      Name: 'test-project-cdk-build',
      Description: 'Build project for CDK synthesis and deployment',
      ServiceRole: {
        'Fn::GetAtt': [
          expect.stringMatching(/CodeBuildRole.*/),
          'Arn',
        ],
      },
    });

    // Deploy Project
    template.hasResourceProperties('AWS::CodeBuild::Project', {
      Name: 'test-project-deploy',
      Description: 'Deploy project for CDK application deployment',
    });
  });

  test('should create S3 artifact bucket', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: expect.stringMatching(/test-project-artifacts-.*/),
      VersioningConfiguration: {
        Status: 'Enabled',
      },
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256',
            },
          },
        ],
      },
    });
  });

  test('should create SNS topic for notifications', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      TopicName: 'test-project-notifications',
      DisplayName: 'Infrastructure Deployment Notifications',
    });
  });

  test('should create CloudTrail for audit logging', () => {
    template.hasResourceProperties('AWS::CloudTrail::Trail', {
      TrailName: 'test-project-audit-trail',
      IncludeGlobalServiceEvents: true,
      IsMultiRegionTrail: true,
      EnableLogFileValidation: true,
    });
  });

  test('should create CloudWatch alarm for pipeline failures', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'test-project-pipeline-failure',
      AlarmDescription: 'Pipeline execution failed',
      MetricName: 'PipelineExecutionFailed',
      Namespace: 'AWS/CodePipeline',
      Statistic: 'Sum',
      Threshold: 1,
    });
  });

  test('should have correct pipeline stages', () => {
    const pipeline = template.findResources('AWS::CodePipeline::Pipeline');
    const pipelineResource = Object.values(pipeline)[0];
    
    expect(pipelineResource.Properties.Stages).toHaveLength(5);
    expect(pipelineResource.Properties.Stages[0].Name).toBe('Source');
    expect(pipelineResource.Properties.Stages[1].Name).toBe('Build');
    expect(pipelineResource.Properties.Stages[2].Name).toBe('Deploy-Dev');
    expect(pipelineResource.Properties.Stages[3].Name).toBe('Approval');
    expect(pipelineResource.Properties.Stages[4].Name).toBe('Deploy-Prod');
  });

  test('should have manual approval action', () => {
    const pipeline = template.findResources('AWS::CodePipeline::Pipeline');
    const pipelineResource = Object.values(pipeline)[0];
    
    const approvalStage = pipelineResource.Properties.Stages.find(
      (stage: any) => stage.Name === 'Approval'
    );
    
    expect(approvalStage).toBeDefined();
    expect(approvalStage.Actions[0].ActionTypeId.Category).toBe('Approval');
    expect(approvalStage.Actions[0].ActionTypeId.Provider).toBe('Manual');
  });

  test('should create IAM role with correct permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'codebuild.amazonaws.com',
            },
          },
        ],
      },
    });
  });

  test('should create outputs', () => {
    template.hasOutput('RepositoryCloneUrl', {
      Description: 'HTTP clone URL for the CodeCommit repository',
    });

    template.hasOutput('PipelineName', {
      Description: 'Name of the CodePipeline',
    });

    template.hasOutput('ArtifactBucketName', {
      Description: 'Name of the S3 bucket for pipeline artifacts',
    });

    template.hasOutput('NotificationTopicArn', {
      Description: 'ARN of the SNS topic for pipeline notifications',
    });
  });

  test('should have correct tags', () => {
    const resources = template.findResources('AWS::CodeCommit::Repository');
    const repositoryResource = Object.values(resources)[0];
    
    expect(repositoryResource.Properties.Tags).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Key: 'Project',
          Value: 'test-project',
        }),
        expect.objectContaining({
          Key: 'Environment',
          Value: 'cicd',
        }),
        expect.objectContaining({
          Key: 'ManagedBy',
          Value: 'CDK',
        }),
      ])
    );
  });
});