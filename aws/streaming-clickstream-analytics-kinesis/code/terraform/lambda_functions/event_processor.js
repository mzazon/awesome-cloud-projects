const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();
const cloudwatch = new AWS.CloudWatch();

const TABLE_PREFIX = '${table_prefix}';
const BUCKET_NAME = '${bucket_name}';

exports.handler = async (event) => {
    console.log('Processing', event.Records.length, 'records');
    
    const promises = event.Records.map(async (record) => {
        try {
            // Decode the Kinesis data
            const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const clickEvent = JSON.parse(payload);
            
            // Process different event types
            await Promise.all([
                processPageView(clickEvent),
                updateSessionMetrics(clickEvent),
                updateRealTimeCounters(clickEvent),
                archiveRawEvent(clickEvent),
                publishMetrics(clickEvent)
            ]);
            
        } catch (error) {
            console.error('Error processing record:', error);
            throw error;
        }
    });
    
    await Promise.all(promises);
    return { statusCode: 200, body: 'Successfully processed events' };
};

async function processPageView(event) {
    if (event.event_type !== 'page_view') return;
    
    const hour = new Date(event.timestamp).toISOString().slice(0, 13);
    
    const params = {
        TableName: `$${TABLE_PREFIX}-page-metrics`,
        Key: {
            page_url: event.page_url,
            timestamp_hour: hour
        },
        UpdateExpression: 'ADD view_count :inc SET last_updated = :now, #ttl = :ttl',
        ExpressionAttributeNames: {
            '#ttl': 'ttl'
        },
        ExpressionAttributeValues: {
            ':inc': 1,
            ':now': Date.now(),
            ':ttl': Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60) // 7 day TTL
        }
    };
    
    await dynamodb.update(params).promise();
}

async function updateSessionMetrics(event) {
    const params = {
        TableName: `$${TABLE_PREFIX}-session-metrics`,
        Key: { session_id: event.session_id },
        UpdateExpression: 'SET last_activity = :now, user_agent = :ua, #ttl = :ttl ADD event_count :inc',
        ExpressionAttributeNames: {
            '#ttl': 'ttl'
        },
        ExpressionAttributeValues: {
            ':now': event.timestamp,
            ':ua': event.user_agent || 'unknown',
            ':inc': 1,
            ':ttl': Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hour TTL
        }
    };
    
    await dynamodb.update(params).promise();
}

async function updateRealTimeCounters(event) {
    const minute = new Date(event.timestamp).toISOString().slice(0, 16);
    
    const params = {
        TableName: `$${TABLE_PREFIX}-counters`,
        Key: {
            metric_name: `events_per_minute_$${event.event_type}`,
            time_window: minute
        },
        UpdateExpression: 'ADD event_count :inc SET #ttl = :ttl',
        ExpressionAttributeNames: {
            '#ttl': 'ttl'
        },
        ExpressionAttributeValues: {
            ':inc': 1,
            ':ttl': Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hour TTL
        }
    };
    
    await dynamodb.update(params).promise();
}

async function archiveRawEvent(event) {
    const date = new Date(event.timestamp);
    const key = `year=$${date.getFullYear()}/month=$${date.getMonth() + 1}/day=$${date.getDate()}/hour=$${date.getHours()}/$${event.session_id}-$${Date.now()}.json`;
    
    const params = {
        Bucket: BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(event),
        ContentType: 'application/json',
        ServerSideEncryption: 'AES256'
    };
    
    await s3.putObject(params).promise();
}

async function publishMetrics(event) {
    const params = {
        Namespace: 'Clickstream/Events',
        MetricData: [
            {
                MetricName: 'EventsProcessed',
                Value: 1,
                Unit: 'Count',
                Dimensions: [
                    {
                        Name: 'EventType',
                        Value: event.event_type
                    }
                ]
            }
        ]
    };
    
    await cloudwatch.putMetricData(params).promise();
}