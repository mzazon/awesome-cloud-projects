import json
import boto3
import qrcode
import io
from datetime import datetime
import uuid
import os

# Initialize S3 client outside handler for connection reuse
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    AWS Lambda handler for QR code generation.
    
    Args:
        event: API Gateway event containing request body with 'text' parameter
        context: Lambda context object
        
    Returns:
        dict: API Gateway response with QR code URL or error message
    """
    try:
        # Parse request body
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event
        
        text = body.get('text', '').strip()
        if not text:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Text parameter is required'})
            }
        
        # Limit text length for security and performance
        if len(text) > 1000:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Text too long (max 1000 characters)'})
            }
        
        # Generate QR code with configurable parameters
        qr = qrcode.QRCode(
            version=1,  # Controls the size of the QR Code
            error_correction=qrcode.constants.ERROR_CORRECT_L,  # Error correction level
            box_size=10,  # Size of each box in pixels
            border=4,  # Thickness of the border (minimum is 4)
        )
        qr.add_data(text)
        qr.make(fit=True)
        
        # Create QR code image with high contrast colors
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert PIL image to bytes
        img_buffer = io.BytesIO()
        img.save(img_buffer, format='PNG')
        img_buffer.seek(0)
        
        # Generate unique filename with timestamp and UUID
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        unique_id = str(uuid.uuid4())[:8]
        filename = f"qr_{timestamp}_{unique_id}.png"
        
        # Get bucket name from environment variable (set by Terraform)
        bucket_name = "${bucket_name}"
        
        # Upload QR code image to S3 with appropriate metadata
        s3_client.put_object(
            Bucket=bucket_name,
            Key=filename,
            Body=img_buffer.getvalue(),
            ContentType='image/png',
            CacheControl='max-age=31536000',  # Cache for 1 year
            Metadata={
                'original-text-length': str(len(text)),
                'generated-timestamp': timestamp,
                'qr-version': '1',
                'error-correction': 'L'
            }
        )
        
        # Generate public URL for the QR code image
        region = boto3.Session().region_name
        url = f"https://{bucket_name}.s3.{region}.amazonaws.com/{filename}"
        
        # Return success response with QR code details
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Cache-Control': 'no-cache'
            },
            'body': json.dumps({
                'message': 'QR code generated successfully',
                'url': url,
                'filename': filename,
                'text_length': len(text),
                'timestamp': timestamp,
                'qr_properties': {
                    'version': 1,
                    'error_correction': 'L',
                    'box_size': 10,
                    'border': 4
                }
            })
        }
        
    except json.JSONDecodeError as e:
        # Handle JSON parsing errors
        print(f"JSON decode error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
        
    except Exception as e:
        # Log error for debugging and return generic error response
        print(f"Error generating QR code: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to generate QR code'
            })
        }