"""Lambda handler for real-time resume processing via S3 events."""

import json
import os
import boto3
import time
from urllib.parse import unquote_plus
from bda_parser.bda_client import BDAResumeParser


def process_with_retry(bda_client, input_s3_uri, output_s3_uri, blueprint_arn, max_retries=3):
    """Process resume with exponential backoff retry using blueprint."""
    
    for attempt in range(max_retries):
        try:
            # Use blueprint-based processing with our hierarchical schema
            invocation_arn = bda_client.process_resume(
                s3_uri=input_s3_uri,
                output_s3_uri=output_s3_uri,
                blueprint_arn=blueprint_arn
            )
            
            status = bda_client.wait_for_completion(invocation_arn)
            return invocation_arn, status
            
        except Exception as e:
            if attempt == max_retries - 1:
                raise e
            
            wait_time = 2 ** attempt
            print(f"Attempt {attempt + 1} failed: {e}. Retrying in {wait_time}s...")
            time.sleep(wait_time)


def lambda_handler(event, context):
    """Process S3 event notifications for resume uploads."""
    
    bucket_name = os.environ['BUCKET_NAME']
    blueprint_arn = os.environ['BLUEPRINT_ARN']
    
    # Initialize BDA client
    bda_client = BDAResumeParser()
    
    results = []
    
    for record in event['Records']:
        try:
            # Parse S3 event
            s3_bucket = record['s3']['bucket']['name']
            s3_key = unquote_plus(record['s3']['object']['key'])
            
            # Skip if not in input/ prefix
            if not s3_key.startswith('input/'):
                continue
                
            print(f"Processing: s3://{s3_bucket}/{s3_key}")
            
            # Generate output path
            filename = s3_key.split('/')[-1].split('.')[0]
            output_key = f"output/{filename}/"
            
            # Process resume with blueprint (hierarchical schema)
            input_s3_uri = f"s3://{s3_bucket}/{s3_key}"
            output_s3_uri = f"s3://{s3_bucket}/{output_key}job_metadata.json"
            
            invocation_arn, status = process_with_retry(
                bda_client, input_s3_uri, output_s3_uri, blueprint_arn
            )
            
            results.append({
                'input_file': s3_key,
                'output_path': output_key,
                'status': status['status'],
                'invocation_arn': invocation_arn
            })
            
        except Exception as e:
            print(f"Error processing {s3_key}: {str(e)}")
            results.append({
                'input_file': s3_key,
                'error': str(e)
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed_files': len(results),
            'results': results
        })
    }
