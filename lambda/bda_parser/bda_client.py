"""Amazon Bedrock Data Automation client for resume parsing."""

import boto3
import json
import os
import time
from typing import Dict, Optional, List
from botocore.exceptions import ClientError
from .config import AWS_REGION, AWS_PROFILE


class BDAResumeParser:
    """Client for processing resumes using Amazon Bedrock Data Automation with custom blueprints."""
    
    def __init__(self, region: str = AWS_REGION, profile: str = None):
        """Initialize BDA client."""
        # In Lambda, use IAM role instead of profile
        if profile and not os.environ.get('AWS_LAMBDA_FUNCTION_NAME'):
            session = boto3.Session(profile_name=profile)
        else:
            session = boto3.Session()
            
        self.bedrock_client = session.client('bedrock-data-automation', region_name=region)
        self.bedrock_runtime_client = session.client('bedrock-data-automation-runtime', region_name=region)
        self.s3_client = session.client('s3', region_name=region)
        self.region = region
    
    def create_blueprint(self, blueprint_name: str, schema: dict) -> str:
        """Create a custom blueprint for resume extraction."""
        try:
            response = self.bedrock_client.create_blueprint(
                blueprintName=blueprint_name,
                type="DOCUMENT",
                schema=json.dumps(schema),
                blueprintStage="LIVE"
            )
            
            if 'blueprint' in response:
                blueprint_arn = response['blueprint']['blueprintArn']
            elif 'blueprintArn' in response:
                blueprint_arn = response['blueprintArn']
            else:
                raise Exception(f"Unexpected response format: {response}")
            
            print(f"✅ Created blueprint: {blueprint_arn}")
            return blueprint_arn
            
        except ClientError as e:
            print(f"Error creating blueprint: {e}")
            raise
    

    
    def _get_profile_arn(self) -> str:
        """Get the data automation profile ARN for the current account."""
        sts_client = boto3.client('sts')
        account_id = sts_client.get_caller_identity()['Account']
        return f"arn:aws:bedrock:{self.region}:{account_id}:data-automation-profile/apac.data-automation-v1"
    
    def process_resume(self, s3_uri: str, output_s3_uri: str, blueprint_arn: Optional[str] = None) -> str:
        """Process resume using BDA with optional custom blueprint."""
        try:
            profile_arn = self._get_profile_arn()
            
            # Build request parameters
            request_params = {
                'inputConfiguration': {
                    's3Uri': s3_uri
                },
                'outputConfiguration': {
                    's3Uri': output_s3_uri
                },
                'dataAutomationProfileArn': profile_arn
            }
            
            # Add blueprint if provided
            if blueprint_arn:
                request_params['blueprints'] = [{'blueprintArn': blueprint_arn}]
            
            response = self.bedrock_runtime_client.invoke_data_automation_async(**request_params)
            return response['invocationArn']
            
        except ClientError as e:
            print(f"Error processing resume: {e}")
            raise
    
    def check_status(self, invocation_arn: str) -> Dict:
        """Check the status of a BDA processing job."""
        try:
            response = self.bedrock_runtime_client.get_data_automation_status(
                invocationArn=invocation_arn
            )
            return response
            
        except ClientError as e:
            print(f"Error checking status: {e}")
            raise
    
    def wait_for_completion(self, invocation_arn: str, 
                          max_wait_time: int = 300) -> Dict:
        """Wait for processing to complete."""
        start_time = time.time()
        
        while time.time() - start_time < max_wait_time:
            status = self.check_status(invocation_arn)
            
            if status['status'] == 'Success':
                print("Processing completed successfully!")
                return status
            elif status['status'] in ['ServiceError', 'ClientError']:
                print(f"Processing failed: {status.get('errorMessage', 'Unknown error')}")
                return status
            
            print(f"Status: {status['status']} - Waiting...")
            time.sleep(10)
        
        raise TimeoutError(f"Processing did not complete within {max_wait_time} seconds")
    
    def download_results(self, local_path: str, invocation_arn: str) -> Dict:
        """Download and parse results from S3."""
        try:
            # Get status to find output location
            status = self.check_status(invocation_arn)
            
            if 'outputConfiguration' not in status or 's3Uri' not in status['outputConfiguration']:
                raise Exception("Output S3 URI not found in status response")
            
            # outputConfiguration.s3Uri points to job_metadata.json, replace with result.json
            output_s3_uri = status['outputConfiguration']['s3Uri']
            result_s3_uri = output_s3_uri.replace('job_metadata.json', '0/custom_output/0/result.json')
            bucket, result_key = result_s3_uri.replace('s3://', '').split('/', 1)
            
            # Download file
            self.s3_client.download_file(bucket, result_key, local_path)
            
            # Parse JSON results
            with open(local_path, 'r') as f:
                results = json.load(f)
            
            return results
            
        except ClientError as e:
            print(f"Error downloading results: {e}")
            raise
    

