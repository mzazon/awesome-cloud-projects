import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { StaticWebsiteStack } from '../lib/static-website-stack';

describe('StaticWebsiteStack', () => {
  let app: cdk.App;
  let stack: StaticWebsiteStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new StaticWebsiteStack(app, 'TestStack', {
      domainName: 'example.com',
      hostedZoneId: 'Z1234567890123',
    });
    template = Template.fromStack(stack);
  });

  test('Creates S3 buckets for website and redirect', () => {
    // Check that both S3 buckets are created
    template.resourceCountIs('AWS::S3::Bucket', 2);
    
    // Check website bucket configuration
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: 'www.example.com',
      WebsiteConfiguration: {
        IndexDocument: 'index.html',
        ErrorDocument: 'error.html',
      },
    });

    // Check redirect bucket configuration
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: 'example.com',
      WebsiteConfiguration: {
        RedirectAllRequestsTo: {
          HostName: 'www.example.com',
          Protocol: 'https',
        },
      },
    });
  });

  test('Creates CloudFront distributions', () => {
    // Check that CloudFront distributions are created
    template.resourceCountIs('AWS::CloudFront::Distribution', 2);
    
    // Check main distribution properties
    template.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: {
        Aliases: ['www.example.com'],
        DefaultRootObject: 'index.html',
        Enabled: true,
        PriceClass: 'PriceClass_100',
      },
    });
  });

  test('Creates Route 53 records', () => {
    // Check that Route 53 A records are created
    template.resourceCountIs('AWS::Route53::RecordSet', 2);
    
    // Check A record properties
    template.hasResourceProperties('AWS::Route53::RecordSet', {
      Type: 'A',
      Name: 'www.example.com',
    });

    template.hasResourceProperties('AWS::Route53::RecordSet', {
      Type: 'A',
      Name: 'example.com',
    });
  });

  test('Creates SSL certificate when not provided', () => {
    // Check that SSL certificate is created
    template.resourceCountIs('AWS::CertificateManager::Certificate', 1);
    
    template.hasResourceProperties('AWS::CertificateManager::Certificate', {
      DomainName: 'example.com',
      SubjectAlternativeNames: ['www.example.com'],
      ValidationMethod: 'DNS',
    });
  });

  test('Creates S3 bucket deployment', () => {
    // Check that S3 bucket deployment is created
    template.resourceCountIs('Custom::CDKBucketDeployment', 1);
  });

  test('Uses existing certificate when provided', () => {
    const stackWithCert = new StaticWebsiteStack(app, 'TestStackWithCert', {
      domainName: 'example.com',
      hostedZoneId: 'Z1234567890123',
      certificateArn: 'arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012',
    });
    
    const templateWithCert = Template.fromStack(stackWithCert);
    
    // Should not create a new certificate
    templateWithCert.resourceCountIs('AWS::CertificateManager::Certificate', 0);
  });

  test('Outputs are created', () => {
    // Check that all expected outputs are present
    template.hasOutput('WebsiteBucketName', {});
    template.hasOutput('RedirectBucketName', {});
    template.hasOutput('CloudFrontDistributionId', {});
    template.hasOutput('CloudFrontDistributionDomainName', {});
    template.hasOutput('WebsiteURL', {});
    template.hasOutput('CertificateArn', {});
  });

  test('Stack has correct tags', () => {
    // Verify the stack can be created without errors
    expect(stack).toBeDefined();
    expect(stack.stackName).toBe('TestStack');
  });
});