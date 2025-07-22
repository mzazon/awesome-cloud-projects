#!/usr/bin/env node
/**
 * AWS CDK TypeScript Application for Static Website Hosting
 * 
 * This CDK application creates a complete static website hosting solution using:
 * - Amazon S3 for storing website content
 * - Amazon CloudFront for global content delivery
 * - AWS Certificate Manager for SSL/TLS certificates
 * - Route 53 for DNS management (optional)
 * 
 * The solution implements security best practices with Origin Access Control (OAC)
 * and follows AWS Well-Architected Framework principles.
 */

import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Configuration interface for the static website stack
 */
interface StaticWebsiteProps extends cdk.StackProps {
  /**
   * Domain name for the website (optional)
   * If provided, Route 53 hosted zone will be used and SSL certificate will be created
   */
  domainName?: string;
  
  /**
   * Whether to create a subdomain (www) alias record
   * @default false
   */
  createWwwAlias?: boolean;
  
  /**
   * Route 53 hosted zone ID (required if domainName is provided)
   */
  hostedZoneId?: string;
  
  /**
   * CloudFront price class to control costs
   * @default PriceClass_100 (North America and Europe)
   */
  priceClass?: cloudfront.PriceClass;
  
  /**
   * Environment tags to apply to all resources
   */
  environmentTags?: { [key: string]: string };
}

/**
 * Static Website Hosting Stack
 * 
 * Creates a complete infrastructure for hosting static websites with:
 * - Secure S3 bucket with private access
 * - Global CloudFront distribution
 * - Optional custom domain with SSL certificate
 * - Comprehensive error handling and logging
 */
class StaticWebsiteStack extends cdk.Stack {
  public readonly websiteBucket: s3.Bucket;
  public readonly logsBucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;
  public readonly certificate?: acm.Certificate;
  public readonly hostedZone?: route53.IHostedZone;
  
  constructor(scope: Construct, id: string, props: StaticWebsiteProps = {}) {
    super(scope, id, props);
    
    // Generate unique suffix for bucket names to avoid conflicts
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-8);
    
    // Create S3 bucket for access logs
    this.logsBucket = new s3.Bucket(this, 'AccessLogsBucket', {
      bucketName: `static-website-logs-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'LogsRetention',
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
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    
    // Create S3 bucket for website content
    this.websiteBucket = new s3.Bucket(this, 'WebsiteBucket', {
      bucketName: `static-website-content-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      intelligentTieringConfigurations: [
        {
          id: 'IntelligentTiering',
          status: s3.IntelligentTieringStatus.ENABLED,
        },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    
    // Create Origin Access Control for secure CloudFront access
    const originAccessControl = new cloudfront.S3OriginAccessControl(this, 'OriginAccessControl', {
      description: 'OAC for static website bucket',
    });
    
    // SSL Certificate for custom domain (if provided)
    if (props.domainName) {
      // Retrieve existing hosted zone
      this.hostedZone = route53.HostedZone.fromHostedZoneAttributes(this, 'HostedZone', {
        hostedZoneId: props.hostedZoneId!,
        zoneName: props.domainName,
      });
      
      // Create SSL certificate with DNS validation
      this.certificate = new acm.Certificate(this, 'SslCertificate', {
        domainName: props.domainName,
        subjectAlternativeNames: props.createWwwAlias ? [`www.${props.domainName}`] : undefined,
        validation: acm.CertificateValidation.fromDns(this.hostedZone),
      });
    }
    
    // Create CloudFront distribution
    this.distribution = new cloudfront.Distribution(this, 'Distribution', {
      comment: `Distribution for ${props.domainName || 'static website'}`,
      defaultRootObject: 'index.html',
      priceClass: props.priceClass || cloudfront.PriceClass.PRICE_CLASS_100,
      
      // Domain names and SSL certificate
      domainNames: props.domainName ? [props.domainName] : undefined,
      certificate: this.certificate,
      
      // Default behavior
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.websiteBucket, {
          originAccessControl,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        compress: true,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
      },
      
      // Error responses
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 404,
          responsePagePath: '/error.html',
          ttl: cdk.Duration.minutes(5),
        },
        {
          httpStatus: 403,
          responseHttpStatus: 404,
          responsePagePath: '/error.html',
          ttl: cdk.Duration.minutes(5),
        },
      ],
      
      // Enable logging
      enableLogging: true,
      logBucket: this.logsBucket,
      logFilePrefix: 'cloudfront-logs/',
      logIncludesCookies: false,
    });
    
    // Grant CloudFront permission to access the S3 bucket
    this.websiteBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudFrontServicePrincipalReadOnly',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
        actions: ['s3:GetObject'],
        resources: [this.websiteBucket.arnForObjects('*')],
        conditions: {
          StringEquals: {
            'AWS:SourceArn': `arn:aws:cloudfront::${this.account}:distribution/${this.distribution.distributionId}`,
          },
        },
      })
    );
    
    // Create Route 53 DNS records (if domain is provided)
    if (props.domainName && this.hostedZone) {
      // Create A record for the domain
      new route53.ARecord(this, 'DomainRecord', {
        zone: this.hostedZone,
        recordName: props.domainName,
        target: route53.RecordTarget.fromAlias(
          new targets.CloudFrontTarget(this.distribution)
        ),
      });
      
      // Create AAAA record for IPv6 support
      new route53.AaaaRecord(this, 'DomainRecordIpv6', {
        zone: this.hostedZone,
        recordName: props.domainName,
        target: route53.RecordTarget.fromAlias(
          new targets.CloudFrontTarget(this.distribution)
        ),
      });
      
      // Create www alias (if requested)
      if (props.createWwwAlias) {
        new route53.ARecord(this, 'WwwRecord', {
          zone: this.hostedZone,
          recordName: `www.${props.domainName}`,
          target: route53.RecordTarget.fromAlias(
            new targets.CloudFrontTarget(this.distribution)
          ),
        });
        
        new route53.AaaaRecord(this, 'WwwRecordIpv6', {
          zone: this.hostedZone,
          recordName: `www.${props.domainName}`,
          target: route53.RecordTarget.fromAlias(
            new targets.CloudFrontTarget(this.distribution)
          ),
        });
      }
    }
    
    // Apply environment tags
    if (props.environmentTags) {
      Object.entries(props.environmentTags).forEach(([key, value]) => {
        cdk.Tags.of(this).add(key, value);
      });
    }
    
    // Add standard tags
    cdk.Tags.of(this).add('Project', 'StaticWebsiteHosting');
    cdk.Tags.of(this).add('CreatedBy', 'CDK');
    
    // Outputs
    new cdk.CfnOutput(this, 'WebsiteBucketName', {
      value: this.websiteBucket.bucketName,
      description: 'S3 bucket name for website content',
      exportName: `${this.stackName}-WebsiteBucketName`,
    });
    
    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: `${this.stackName}-DistributionId`,
    });
    
    new cdk.CfnOutput(this, 'CloudFrontDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: `${this.stackName}-CloudFrontDomain`,
    });
    
    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: props.domainName 
        ? `https://${props.domainName}` 
        : `https://${this.distribution.distributionDomainName}`,
      description: 'Website URL',
      exportName: `${this.stackName}-WebsiteURL`,
    });
    
    if (this.certificate) {
      new cdk.CfnOutput(this, 'CertificateArn', {
        value: this.certificate.certificateArn,
        description: 'SSL certificate ARN',
        exportName: `${this.stackName}-CertificateArn`,
      });
    }
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context
const domainName = app.node.tryGetContext('domainName');
const hostedZoneId = app.node.tryGetContext('hostedZoneId');
const createWwwAlias = app.node.tryGetContext('createWwwAlias') === 'true';
const environment = app.node.tryGetContext('environment') || 'dev';

// Create the stack
const stack = new StaticWebsiteStack(app, 'StaticWebsiteStack', {
  description: 'Static website hosting with S3, CloudFront, and optional custom domain',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  domainName,
  hostedZoneId,
  createWwwAlias,
  priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
  environmentTags: {
    Environment: environment,
    Application: 'StaticWebsite',
  },
});

// Synthesize the app
app.synth();