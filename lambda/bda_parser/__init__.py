"""BDA Resume Parser - Amazon Bedrock Data Automation client for resume parsing."""

from .bda_client import BDAResumeParser
from .config import S3_BUCKET, S3_INPUT_PREFIX, S3_OUTPUT_PREFIX

__all__ = ['BDAResumeParser', 'S3_BUCKET', 'S3_INPUT_PREFIX', 'S3_OUTPUT_PREFIX']