"""CDK stack for BDA real-time resume processing infrastructure."""

import json
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_s3_notifications as s3n,
    aws_sqs as sqs,
    aws_bedrock as bedrock,
    Duration,
    RemovalPolicy,
    CfnOutput
)
from constructs import Construct


class BDAResumeStack(Stack):
    """Infrastructure stack for real-time BDA resume processing."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # S3 bucket for resumes and results
        bucket = s3.Bucket(self, "BDAResumeBucket",
            bucket_name=f"bda-resume-processing-{self.account}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Dead Letter Queue for failed processing
        dlq = sqs.Queue(self, "BDAProcessingDLQ",
            queue_name="bda-resume-processing-dlq",
            retention_period=Duration.days(14)
        )

        # Lambda execution role
        lambda_role = iam.Role(self, "BDALambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add permissions for BDA, S3, and SQS
        lambda_role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "bedrock:InvokeDataAutomationAsync",
                "bedrock:GetDataAutomationStatus",
                "bedrock:GetDataAutomationArtifact"
            ],
            resources=["*"]
        ))
        
        bucket.grant_read_write(lambda_role)
        dlq.grant_send_messages(lambda_role)

        # Lambda function for BDA processing using regular Function (no Docker needed)
        processor_function = _lambda.Function(self, "BDAProcessorFunction",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="handler.lambda_handler",
            code=_lambda.Code.from_asset("../lambda"),
            role=lambda_role,
            timeout=Duration.minutes(15),
            memory_size=1024,
            dead_letter_queue=dlq,
            environment={
                "BUCKET_NAME": bucket.bucket_name,
                "USE_DEFAULT_PROCESSING": "true"
            }
        )

        # S3 event notification to trigger Lambda
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(processor_function),
            s3.NotificationKeyFilter(prefix="input/")
        )

        # Load blueprint schema
        with open("../lambda/bda_parser/blueprint_schema.json", "r") as f:
            blueprint_schema = json.load(f)

        # Create BDA Blueprint in DEVELOPMENT stage (we'll promote to LIVE later)
        blueprint = bedrock.CfnBlueprint(self, "ResumeParserBlueprint",
            blueprint_name=f"resume-parser-hierarchical-{self.account}",
            type="DOCUMENT",
            schema=blueprint_schema
            # Note: No blueprint_stage specified = defaults to DEVELOPMENT in CDK
        )

        # Create BDA Data Automation Project with custom output configuration
        bda_project = bedrock.CfnDataAutomationProject(self, "ResumeParserProject",
            project_name=f"resume-parser-project-{self.account}",
            project_description="Automated resume parsing using hierarchical blueprint",
            standard_output_configuration={
                "document": {
                    "extraction": {
                        "granularity": {
                            "types": ["DOCUMENT"]
                        },
                        "boundingBox": {
                            "state": "ENABLED"
                        }
                    }
                }
            },
            custom_output_configuration={
                "blueprints": [
                    {
                        "blueprintArn": blueprint.attr_blueprint_arn
                    }
                ]
            }
        )

        # Update Lambda environment with blueprint and project ARNs
        processor_function.add_environment("BLUEPRINT_ARN", blueprint.attr_blueprint_arn)
        processor_function.add_environment("PROJECT_ARN", bda_project.attr_project_arn)

        # CDK Outputs for easy access
        CfnOutput(self, "BucketName",
            value=bucket.bucket_name,
            description="S3 bucket for resume processing"
        )
        
        CfnOutput(self, "LambdaFunctionName", 
            value=processor_function.function_name,
            description="Lambda function for BDA processing"
        )
        
        CfnOutput(self, "BlueprintArn",
            value=blueprint.attr_blueprint_arn,
            description="BDA Blueprint ARN (for promotion to LIVE)"
        )
        
        CfnOutput(self, "ProjectArn",
            value=bda_project.attr_project_arn,
            description="BDA Project ARN (for promotion to LIVE)"
        )
        


        # Output values for reference
        self.bucket_name = bucket.bucket_name
        self.lambda_function_name = processor_function.function_name
        self.blueprint_arn = blueprint.attr_blueprint_arn
        self.project_arn = bda_project.attr_project_arn
