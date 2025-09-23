#!/usr/bin/env python3
"""CDK app for BDA real-time resume processing."""

import aws_cdk as cdk
from stacks.bda_stack import BDAResumeStack

app = cdk.App()

BDAResumeStack(app, "BDAResumeStack",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region="ap-south-1"
    )
)

app.synth()
