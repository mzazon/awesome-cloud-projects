import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { UrlShortenerStack } from '../lib/url-shortener-stack';

describe('UrlShortenerStack', () => {
  let app: cdk.App;
  let stack: UrlShortenerStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new UrlShortenerStack(app, 'TestUrlShortenerStack');
    template = Template.fromStack(stack);
  });

  test('Creates DynamoDB Table', () => {
    template.hasResourceProperties('AWS::DynamoDB::Table', {
      BillingMode: 'PAY_PER_REQUEST',
      AttributeDefinitions: [
        {
          AttributeName: 'short_id',
          AttributeType: 'S',
        },
      ],
      KeySchema: [
        {
          AttributeName: 'short_id',
          KeyType: 'HASH',
        },
      ],
      PointInTimeRecoverySpecification: {
        PointInTimeRecoveryEnabled: true,
      },
      SSESpecification: {
        SSEEnabled: true,
      },
    });
  });

  test('Creates Lambda Function', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.9',
      Handler: 'lambda_function.lambda_handler',
      Timeout: 30,
      MemorySize: 256,
    });
  });

  test('Creates API Gateway REST API', () => {
    template.hasResourceProperties('AWS::ApiGateway::RestApi', {
      Name: 'URL Shortener API',
      Description: 'Serverless URL Shortener Service',
    });
  });

  test('Creates API Gateway Deployment', () => {
    template.hasResourceProperties('AWS::ApiGateway::Deployment', {
      StageName: 'prod',
    });
  });

  test('Creates Lambda IAM Role with DynamoDB Permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com',
            },
          },
        ],
        Version: '2012-10-17',
      },
    });

    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: [
          {
            Action: [
              'dynamodb:GetItem',
              'dynamodb:PutItem',
              'dynamodb:UpdateItem',
              'dynamodb:DeleteItem',
              'dynamodb:Query',
              'dynamodb:Scan',
            ],
            Effect: 'Allow',
            Resource: {
              'Fn::GetAtt': [
                expect.stringMatching(/UrlShortenerTable/),
                'Arn',
              ],
            },
          },
        ],
        Version: '2012-10-17',
      },
    });
  });

  test('Creates CloudWatch Log Group', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/aws/apigateway/url-shortener',
      RetentionInDays: 7,
    });
  });

  test('Configures API Gateway Method for POST /shorten', () => {
    template.hasResourceProperties('AWS::ApiGateway::Method', {
      HttpMethod: 'POST',
      ResourceId: {
        Ref: expect.stringMatching(/shorten/),
      },
    });
  });

  test('Configures API Gateway Method for GET /{proxy+}', () => {
    template.hasResourceProperties('AWS::ApiGateway::Method', {
      HttpMethod: 'GET',
      ResourceId: {
        Ref: expect.stringMatching(/proxyANY/),
      },
    });
  });

  test('Has correct number of outputs', () => {
    const outputs = template.findOutputs('*');
    expect(Object.keys(outputs)).toHaveLength(4);
  });

  test('Outputs include API Gateway URL', () => {
    template.hasOutput('ApiGatewayUrl', {
      Description: 'URL Shortener API Gateway URL',
      Export: {
        Name: 'UrlShortenerApiUrl',
      },
    });
  });

  test('Lambda function has environment variables', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: {
          TABLE_NAME: {
            Ref: expect.stringMatching(/UrlShortenerTable/),
          },
        },
      },
    });
  });

  test('API Gateway has CORS enabled', () => {
    template.hasResourceProperties('AWS::ApiGateway::Method', {
      HttpMethod: 'OPTIONS',
    });
  });

  test('Lambda function has proper logging configuration', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      LoggingConfig: {
        LogGroup: {
          Ref: expect.stringMatching(/UrlShortenerFunction.*LogGroup/),
        },
      },
    });
  });

  test('Stack has proper tags', () => {
    const dynamoDbTable = template.findResources('AWS::DynamoDB::Table');
    const tableLogicalId = Object.keys(dynamoDbTable)[0];
    
    expect(dynamoDbTable[tableLogicalId].Properties.Tags).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Key: 'Project',
          Value: 'URLShortener',
        }),
        expect.objectContaining({
          Key: 'Environment',
          Value: 'Development',
        }),
      ])
    );
  });

  test('API Gateway has throttling configured', () => {
    template.hasResourceProperties('AWS::ApiGateway::Stage', {
      ThrottleSettings: {
        RateLimit: 1000,
        BurstLimit: 2000,
      },
    });
  });

  test('API Gateway has access logging configured', () => {
    template.hasResourceProperties('AWS::ApiGateway::Stage', {
      AccessLogSetting: {
        DestinationArn: expect.any(Object),
        Format: expect.stringContaining('requestTime'),
      },
    });
  });
});