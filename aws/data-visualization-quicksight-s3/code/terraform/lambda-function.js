/**
 * AWS Lambda Function for Data Pipeline Automation
 * Triggers Glue crawlers and ETL jobs when new data is uploaded to S3
 */

const AWS = require('aws-sdk');

// Initialize AWS services
const glue = new AWS.Glue();
const cloudWatch = new AWS.CloudWatch();

// Environment variables
const PROJECT_NAME = process.env.PROJECT_NAME;
const GLUE_DATABASE = process.env.GLUE_DATABASE;

// Configuration
const CRAWLER_WAIT_TIME = 60000; // 60 seconds
const MAX_RETRIES = 3;
const RETRY_DELAY = 30000; // 30 seconds

/**
 * Main Lambda handler function
 */
exports.handler = async (event, context) => {
    console.log('Lambda function started');
    console.log('Event received:', JSON.stringify(event, null, 2));
    console.log('Context:', JSON.stringify(context, null, 2));
    
    try {
        // Process each S3 event record
        const results = [];
        
        for (const record of event.Records) {
            if (record.eventSource === 'aws:s3' && record.eventName.startsWith('ObjectCreated')) {
                const result = await processS3Event(record);
                results.push(result);
            }
        }
        
        // Send custom CloudWatch metrics
        await sendCustomMetrics(results);
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Pipeline automation completed successfully',
                results: results,
                processedRecords: results.length
            })
        };
        
    } catch (error) {
        console.error('Lambda function failed:', error);
        
        // Send failure metric
        await sendFailureMetric(error);
        
        throw error;
    }
};

/**
 * Process individual S3 event
 */
async function processS3Event(record) {
    const bucketName = record.s3.bucket.name;
    const objectKey = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));
    const eventName = record.eventName;
    
    console.log(`Processing S3 event: ${eventName}`);
    console.log(`Bucket: ${bucketName}`);
    console.log(`Object: ${objectKey}`);
    
    const result = {
        bucket: bucketName,
        key: objectKey,
        event: eventName,
        timestamp: new Date().toISOString(),
        success: false,
        actions: []
    };
    
    try {
        // Check if the uploaded file is in the sales-data directory
        if (objectKey.startsWith('sales-data/')) {
            console.log('New sales data file detected, triggering pipeline...');
            
            // Step 1: Trigger raw data crawler
            const crawlerResult = await triggerCrawlerWithRetry(`${PROJECT_NAME}-raw-crawler`);
            result.actions.push(crawlerResult);
            
            if (crawlerResult.success) {
                // Step 2: Wait for crawler to complete, then trigger ETL job
                setTimeout(async () => {
                    try {
                        await triggerETLJobWithRetry(`${PROJECT_NAME}-etl-job`);
                        console.log('ETL job triggered successfully after crawler completion');
                    } catch (error) {
                        console.error('Failed to trigger ETL job after crawler:', error);
                    }
                }, CRAWLER_WAIT_TIME);
            }
            
            result.success = true;
            
        } else {
            console.log(`File ${objectKey} is not in sales-data directory, skipping pipeline trigger`);
            result.success = true;
            result.actions.push({
                action: 'skip',
                reason: 'File not in sales-data directory'
            });
        }
        
    } catch (error) {
        console.error(`Error processing S3 event for ${objectKey}:`, error);
        result.error = error.message;
    }
    
    return result;
}

/**
 * Trigger Glue crawler with retry logic
 */
async function triggerCrawlerWithRetry(crawlerName, retryCount = 0) {
    console.log(`Triggering crawler: ${crawlerName} (attempt ${retryCount + 1})`);
    
    try {
        const params = { Name: crawlerName };
        await glue.startCrawler(params).promise();
        
        console.log(`Successfully started crawler: ${crawlerName}`);
        return {
            action: 'start_crawler',
            resource: crawlerName,
            success: true,
            attempt: retryCount + 1
        };
        
    } catch (error) {
        if (error.code === 'CrawlerRunningException') {
            console.log(`Crawler ${crawlerName} is already running`);
            return {
                action: 'start_crawler',
                resource: crawlerName,
                success: true,
                note: 'Already running',
                attempt: retryCount + 1
            };
        } else if (retryCount < MAX_RETRIES) {
            console.log(`Crawler trigger failed, retrying in ${RETRY_DELAY}ms...`);
            await sleep(RETRY_DELAY);
            return await triggerCrawlerWithRetry(crawlerName, retryCount + 1);
        } else {
            console.error(`Failed to start crawler ${crawlerName} after ${MAX_RETRIES + 1} attempts:`, error);
            throw error;
        }
    }
}

/**
 * Trigger Glue ETL job with retry logic
 */
async function triggerETLJobWithRetry(jobName, retryCount = 0) {
    console.log(`Triggering ETL job: ${jobName} (attempt ${retryCount + 1})`);
    
    try {
        const params = { 
            JobName: jobName,
            Arguments: {
                '--SOURCE_DATABASE': GLUE_DATABASE,
                '--job-bookmark-option': 'job-bookmark-enable'
            }
        };
        
        const result = await glue.startJobRun(params).promise();
        
        console.log(`Successfully started ETL job: ${jobName}, Run ID: ${result.JobRunId}`);
        return {
            action: 'start_etl_job',
            resource: jobName,
            jobRunId: result.JobRunId,
            success: true,
            attempt: retryCount + 1
        };
        
    } catch (error) {
        if (retryCount < MAX_RETRIES) {
            console.log(`ETL job trigger failed, retrying in ${RETRY_DELAY}ms...`);
            await sleep(RETRY_DELAY);
            return await triggerETLJobWithRetry(jobName, retryCount + 1);
        } else {
            console.error(`Failed to start ETL job ${jobName} after ${MAX_RETRIES + 1} attempts:`, error);
            throw error;
        }
    }
}

/**
 * Check crawler status
 */
async function getCrawlerStatus(crawlerName) {
    try {
        const params = { Name: crawlerName };
        const result = await glue.getCrawler(params).promise();
        return result.Crawler.State;
    } catch (error) {
        console.error(`Error getting crawler status for ${crawlerName}:`, error);
        return 'UNKNOWN';
    }
}

/**
 * Check ETL job status
 */
async function getJobRunStatus(jobName, jobRunId) {
    try {
        const params = { 
            JobName: jobName,
            RunId: jobRunId
        };
        const result = await glue.getJobRun(params).promise();
        return result.JobRun.JobRunState;
    } catch (error) {
        console.error(`Error getting job run status for ${jobName}/${jobRunId}:`, error);
        return 'UNKNOWN';
    }
}

/**
 * Send custom CloudWatch metrics
 */
async function sendCustomMetrics(results) {
    try {
        const successCount = results.filter(r => r.success).length;
        const failureCount = results.filter(r => !r.success).length;
        
        const metrics = [
            {
                MetricName: 'PipelineTriggersSuccess',
                Value: successCount,
                Unit: 'Count',
                Dimensions: [
                    {
                        Name: 'ProjectName',
                        Value: PROJECT_NAME
                    }
                ]
            },
            {
                MetricName: 'PipelineTriggersFailure',
                Value: failureCount,
                Unit: 'Count',
                Dimensions: [
                    {
                        Name: 'ProjectName',
                        Value: PROJECT_NAME
                    }
                ]
            }
        ];
        
        const params = {
            Namespace: 'DataVisualizationPipeline',
            MetricData: metrics
        };
        
        await cloudWatch.putMetricData(params).promise();
        console.log('Custom metrics sent to CloudWatch');
        
    } catch (error) {
        console.error('Failed to send custom metrics:', error);
        // Don't throw error as this is not critical
    }
}

/**
 * Send failure metric to CloudWatch
 */
async function sendFailureMetric(error) {
    try {
        const params = {
            Namespace: 'DataVisualizationPipeline',
            MetricData: [
                {
                    MetricName: 'LambdaExecutionFailures',
                    Value: 1,
                    Unit: 'Count',
                    Dimensions: [
                        {
                            Name: 'ProjectName',
                            Value: PROJECT_NAME
                        },
                        {
                            Name: 'ErrorType',
                            Value: error.code || 'Unknown'
                        }
                    ]
                }
            ]
        };
        
        await cloudWatch.putMetricData(params).promise();
        console.log('Failure metric sent to CloudWatch');
        
    } catch (metricError) {
        console.error('Failed to send failure metric:', metricError);
    }
}

/**
 * Utility function to sleep for specified milliseconds
 */
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Get current timestamp in ISO format
 */
function getCurrentTimestamp() {
    return new Date().toISOString();
}

/**
 * Validate environment variables
 */
function validateEnvironment() {
    if (!PROJECT_NAME) {
        throw new Error('PROJECT_NAME environment variable is required');
    }
    if (!GLUE_DATABASE) {
        throw new Error('GLUE_DATABASE environment variable is required');
    }
}