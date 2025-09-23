#!/usr/bin/env python3
"""Script to promote blueprint and project from DEVELOPMENT to LIVE stage."""

import boto3
import json
import sys
import subprocess
from pathlib import Path


def get_cdk_outputs(stack_name: str = "BDAResumeStack") -> dict:
    """Get CDK stack outputs."""
    try:
        # Change to infrastructure directory
        infrastructure_dir = Path(__file__).parent.parent / "infrastructure"
        
        # Run CDK list to get stack outputs
        result = subprocess.run(
            ["uv", "run", "cdk", "list", "--json"],
            cwd=infrastructure_dir,
            capture_output=True,
            text=True,
            check=True
        )
        
        # Get stack outputs
        result = subprocess.run(
            ["aws", "cloudformation", "describe-stacks", 
             "--stack-name", stack_name, "--query", "Stacks[0].Outputs", "--region", "ap-south-1"],
            cwd=infrastructure_dir,
            capture_output=True,
            text=True,
            check=True
        )
        
        outputs = json.loads(result.stdout)
        
        # Convert to dict for easy access
        output_dict = {}
        for output in outputs:
            output_dict[output["OutputKey"]] = output["OutputValue"]
            
        return output_dict
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error getting CDK outputs: {e}")
        print("Make sure the stack is deployed: cd infrastructure && uv run cdk deploy")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error parsing CDK outputs: {e}")
        sys.exit(1)


def promote_to_live(blueprint_arn: str, project_arn: str, region: str = "ap-south-1"):
    """Promote blueprint and project from DEVELOPMENT to LIVE stage."""
    
    client = boto3.client("bedrock-data-automation", region_name=region)
    
    try:
        # Get current blueprint details
        print(f"Getting blueprint details...")
        blueprint_response = client.get_blueprint(blueprintArn=blueprint_arn)
        blueprint = blueprint_response["blueprint"]
        
        # Check if already in LIVE stage
        current_stage = blueprint.get("blueprintStage", "DEVELOPMENT")
        if current_stage == "LIVE":
            print(f"✅ Blueprint is already in LIVE stage")
            print(f"Blueprint ARN: {blueprint_arn}")
            print(f"✅ Project will automatically use LIVE blueprint")
            print(f"\n🎉 Ready for production!")
            print(f"Blueprint is already in LIVE stage and ready for production workloads!")
            return
        
        # Promote blueprint to LIVE with current schema
        print(f"Promoting blueprint from {current_stage} to LIVE stage...")
        print(f"Blueprint ARN: {blueprint_arn}")
        client.update_blueprint(
            blueprintArn=blueprint_arn,
            blueprintStage="LIVE",
            schema=blueprint["schema"]
        )
        print(f"✅ Blueprint promoted to LIVE")
        
        # Note: Projects don't have stages in the same way - they use blueprints
        print(f"✅ Project will automatically use LIVE blueprint")
        
        print(f"\n🎉 Ready for production!")
        print(f"Blueprint is now in LIVE stage and ready for production workloads!")
        
    except Exception as e:
        print(f"❌ Error promoting to LIVE: {str(e)}")
        sys.exit(1)


def main():
    """Main function."""
    print("📋 Reading CDK outputs...")
    
    # Get ARNs from CDK outputs
    outputs = get_cdk_outputs()
    
    blueprint_arn = outputs.get("BlueprintArn")
    project_arn = outputs.get("ProjectArn")
    
    if not blueprint_arn or not project_arn:
        print("❌ Could not find BlueprintArn or ProjectArn in CDK outputs")
        print("Available outputs:", list(outputs.keys()))
        sys.exit(1)
    
    print(f"Found Blueprint ARN: {blueprint_arn}")
    print(f"Found Project ARN: {project_arn}")
    print()
    
    # Promote to LIVE
    promote_to_live(blueprint_arn, project_arn)


if __name__ == "__main__":
    main()