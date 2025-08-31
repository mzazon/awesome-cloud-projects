import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { KnowledgeManagementAssistantStack } from '../lib/knowledge-management-assistant-stack';

describe('KnowledgeManagementAssistantStack', () => {
  let app: cdk.App;
  let stack: KnowledgeManagementAssistantStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new KnowledgeManagementAssistantStack(app, 'TestStack', {
      enableCdkNag: false, // Disable CDK Nag for testing
    });
    template = Template.fromStack(stack);
  });

  describe('S3 Bucket', () => {
    test('creates S3 bucket with security features', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        VersioningConfiguration: {
          Status: 'Enabled'
        },
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [{
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256'
            }
          }]
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true
        }
      });
    });

    test('applies lifecycle configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: Match.arrayWith([
            Match.objectLike({
              Id: 'TransitionToIA',
              Status: 'Enabled',
              Transitions: Match.arrayWith([
                {
                  StorageClass: 'STANDARD_IA',
                  TransitionInDays: 30
                },
                {
                  StorageClass: 'GLACIER',
                  TransitionInDays: 90
                }
              ])
            })
          ])
        }
      });
    });
  });

  describe('Bedrock Knowledge Base', () => {
    test('creates vector knowledge base', () => {
      template.hasResourceProperties('AWS::Bedrock::KnowledgeBase', {
        Name: Match.stringLikeRegexp('enterprise-knowledge-base-.*'),
        Description: 'Enterprise knowledge base for company policies and procedures',
        KnowledgeBaseConfiguration: {
          Type: 'VECTOR',
          VectorKnowledgeBaseConfiguration: {
            EmbeddingModelArn: Match.stringLikeRegexp('arn:aws:bedrock:.*::foundation-model/amazon.titan-embed-text-v2:0')
          }
        }
      });
    });

    test('creates S3 data source', () => {
      template.hasResourceProperties('AWS::Bedrock::DataSource', {
        DataSourceConfiguration: {
          Type: 'S3',
          S3Configuration: {
            BucketArn: Match.anyValue()
          }
        },
        VectorIngestionConfiguration: {
          ChunkingConfiguration: {
            ChunkingStrategy: 'FIXED_SIZE',
            FixedSizeChunkingConfiguration: {
              MaxTokens: 300,
              OverlapPercentage: 20
            }
          },
          ParsingConfiguration: {
            ParsingStrategy: 'BEDROCK_FOUNDATION_MODEL',
            BedrockFoundationModelConfiguration: {
              ModelArn: Match.stringLikeRegexp('arn:aws:bedrock:.*::foundation-model/anthropic.claude-3-5-sonnet-.*')
            }
          }
        }
      });
    });
  });

  describe('Bedrock Agent', () => {
    test('creates Bedrock agent with proper configuration', () => {
      template.hasResourceProperties('AWS::Bedrock::Agent', {
        AgentName: Match.stringLikeRegexp('knowledge-assistant-.*'),
        Description: 'Enterprise knowledge management assistant powered by Claude 3.5 Sonnet',
        FoundationModel: Match.stringLikeRegexp('anthropic.claude-3-5-sonnet-.*'),
        IdleSessionTTLInSeconds: 1800
      });
    });

    test('associates knowledge base with agent', () => {
      template.hasResourceProperties('AWS::Bedrock::AgentKnowledgeBaseAssociation', {
        AgentId: Match.anyValue(),
        KnowledgeBaseId: Match.anyValue(),
        KnowledgeBaseState: 'ENABLED'
      });
    });
  });

  describe('Lambda Function', () => {
    test('creates Lambda function with correct configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('bedrock-agent-proxy-.*'),
        Runtime: 'python3.12',
        Handler: 'index.lambda_handler',
        Timeout: 30,
        MemorySize: 256,
        Environment: {
          Variables: {
            AGENT_ID: Match.anyValue(),
            AGENT_ALIAS_ID: 'TSTALIASID',
            LOG_LEVEL: 'INFO'
          }
        }
      });
    });

    test('creates CloudWatch log group', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: Match.stringLikeRegexp('/aws/lambda/bedrock-agent-proxy-.*'),
        RetentionInDays: 7
      });
    });

    test('grants Bedrock permissions to Lambda', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: ['bedrock:InvokeAgent'],
              Resource: Match.anyValue()
            })
          ])
        }
      });
    });
  });

  describe('API Gateway', () => {
    test('creates REST API', () => {
      template.hasResourceProperties('AWS::ApiGateway::RestApi', {
        Name: Match.stringLikeRegexp('knowledge-management-api-.*'),
        Description: 'Knowledge Management Assistant API with Bedrock Agents',
        EndpointConfiguration: {
          Types: ['REGIONAL']
        }
      });
    });

    test('creates deployment with proper stage', () => {
      template.hasResourceProperties('AWS::ApiGateway::Deployment', {
        StageName: 'prod'
      });
    });

    test('enables CORS', () => {
      template.hasResourceProperties('AWS::ApiGateway::Method', {
        HttpMethod: 'OPTIONS',
        Integration: {
          Type: 'MOCK'
        }
      });
    });
  });

  describe('IAM Roles and Policies', () => {
    test('creates appropriate IAM roles', () => {
      // Check for Lambda execution role
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Principal: {
                Service: 'lambda.amazonaws.com'
              },
              Action: 'sts:AssumeRole'
            })
          ])
        }
      });

      // Check for Bedrock service role
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Principal: {
                Service: 'bedrock.amazonaws.com'
              },
              Action: 'sts:AssumeRole'
            })
          ])
        }
      });
    });
  });

  describe('Stack Outputs', () => {
    test('exports important resource information', () => {
      template.hasOutput('DocumentBucketName', {
        Description: 'S3 bucket for storing enterprise documents'
      });

      template.hasOutput('KnowledgeBaseId', {
        Description: 'Amazon Bedrock Knowledge Base ID'
      });

      template.hasOutput('BedrockAgentId', {
        Description: 'Amazon Bedrock Agent ID'
      });

      template.hasOutput('ApiEndpoint', {
        Description: 'API Gateway endpoint URL for knowledge management queries'
      });

      template.hasOutput('QueryEndpoint', {
        Description: 'Complete query endpoint URL for POST requests'
      });
    });
  });

  describe('Resource Count Validation', () => {
    test('creates expected number of resources', () => {
      // Verify we have the core resources
      template.resourceCountIs('AWS::S3::Bucket', 1);
      template.resourceCountIs('AWS::Bedrock::KnowledgeBase', 1);
      template.resourceCountIs('AWS::Bedrock::Agent', 1);
      template.resourceCountIs('AWS::Lambda::Function', 1);
      template.resourceCountIs('AWS::ApiGateway::RestApi', 1);
      
      // Should have multiple IAM roles (Lambda, Bedrock, S3 notification, etc.)
      template.resourcePropertiesCountIs('AWS::IAM::Role', {}, 4);
    });
  });

  describe('Custom Configuration', () => {
    test('accepts custom bucket name', () => {
      const customStack = new KnowledgeManagementAssistantStack(app, 'CustomStack', {
        bucketName: 'my-custom-bucket-name',
        enableCdkNag: false,
      });
      
      const customTemplate = Template.fromStack(customStack);
      customTemplate.hasResourceProperties('AWS::S3::Bucket', {
        BucketName: 'my-custom-bucket-name'
      });
    });
  });
});