# BDA Resume Parser - Comprehensive Pricing Estimate (2025)

**Project:** Real-time resume processing using Amazon Bedrock Data Automation  
**Region:** Asia Pacific (Mumbai) - ap-south-1  
**Date:** September 2025  
**Pricing Source:** AWS Pricing API via MCP Server

## Executive Summary

This BDA resume parser project uses Amazon Bedrock Data Automation with custom blueprints for hierarchical data extraction. Based on current AWS pricing data, the estimated monthly cost for processing 1,000 resumes (2 pages average) is **$80.50-$80.55**, with Bedrock Data Automation representing 99%+ of the total infrastructure costs.

## Architecture Overview

The project implements a real-time, event-driven architecture:
- **S3 Upload** → Automatic trigger via S3 Event Notifications
- **Lambda Processing** → BDA hierarchical blueprint extraction  
- **Structured Output** → Organized JSON results saved to S3
- **Error Handling** → DLQ + monitoring for failures

## Detailed Pricing Analysis

**Pricing Validation:** The following analysis is based on official AWS Bedrock Data Automation pricing documentation and confirmed through AWS Pricing API data.

### 1. Amazon Bedrock Data Automation (Primary Cost Driver)

**Service Configuration:**
- Custom blueprint with hierarchical schema (4 main sections: Personal Info, Education, Experience, Skills)
- **Exact field count: 20 fields** (5 fields per section)
- Document processing with structured field extraction
- Development → Live promotion workflow

**Pricing Structure (Confirmed from AWS Documentation):**
- **Documents Custom Output**: $0.040 per page processed (for blueprints with ≤30 fields)
- **Documents Standard Output**: $0.010 per page processed
- **Additional Field Surcharge**: $0.0005 per field per page (only for blueprints >30 fields)

**Monthly Cost Calculation (1,000 resumes, 2 pages avg):**
- Pages processed: 2,000 pages
- Blueprint field count: 20 fields (under 30-field threshold)
- Base custom pricing applies: 2,000 × $0.040 = **$80.00/month**
- Additional field charges: **$0.00** (20 fields ≤ 30 field limit)
- **Total BDA Cost: $80.00/month**

**Blueprint Field Breakdown:**
- Personal Info: 5 fields (full_name, email, phone, address, linkedin)
- Educational Info: 5 fields (institution, degree, graduation_year, gpa, field_of_study)
- Experience: 5 fields (current_position, current_company, years_total, key_achievements, previous_roles)
- Skills: 5 fields (technical, soft, languages, certifications, tools)
- **Total: 20 fields** ✅ (No additional field charges)

### 2. AWS Lambda

**Configuration:**
- Memory: 1024 MB (1 GB)
- Runtime: Python 3.11
- Timeout: 15 minutes
- Average execution: 30 seconds per resume
- Requests: 1,000/month

**Pricing (Asia Pacific Mumbai):**
- **Requests**: $0.0000002 per request
- **Compute (x86)**: $0.0000166667 per GB-second (Tier 1)

**Monthly Cost Calculation:**
- Request charges: 1,000 × $0.0000002 = **$0.0002**
- Compute charges: 1,000 × 30s × 1GB × $0.0000166667 = **$0.50**
- **Total Lambda: $0.50/month**

**Free Tier Benefits:**
- First 12 months: 1M requests/month free
- First 12 months: 400,000 GB-seconds/month free
- **Effective Lambda cost in first year: $0.00**

### 3. Amazon S3

**Storage Requirements:**
- Input: 1,000 resumes × 2MB = 2GB
- Output: 1,000 JSON files × 10KB = 0.01GB
- Total storage: ~2GB/month

**Pricing (Asia Pacific Mumbai):**
- **Standard Storage**: $0.025 per GB/month (first 50TB)

**Monthly Cost Calculation:**
- Storage: 2GB × $0.025 = **$0.05/month**

**Free Tier Benefits:**
- First 12 months: 5GB storage free
- **Effective S3 cost in first year: $0.00**

### 4. Amazon SQS (Dead Letter Queue)

**Usage:** Error handling only
- Estimated: 10 messages/month (1% failure rate)
- **Standard Queue**: $0.0000004 per request

**Monthly Cost:**
- 10 requests × $0.0000004 = **$0.000004** (negligible)

**Free Tier:**
- 1 million requests/month free permanently
- **Effective SQS cost: $0.00**

## Total Monthly Cost Summary

| Service | Monthly Cost | Free Tier Benefit | After Free Tier |
|---------|-------------|-------------------|-----------------|
| **Bedrock Data Automation** | **$80.00** | None | **$80.00** |
| AWS Lambda | $0.50 | $0.50 (first year) | $0.50 |
| Amazon S3 | $0.05 | $0.05 (first year) | $0.05 |
| Amazon SQS | $0.00 | Covered by free tier | $0.00 |
| **Total (First Year)** | **$80.00** | **$0.55 savings** | **$80.00** |
| **Total (After First Year)** | **$80.55** | N/A | **$80.55** |

## Cost Scaling Analysis

### Volume Impact on Monthly Costs

| Monthly Resumes | BDA Cost | Lambda Cost | S3 Cost | Total Cost |
|----------------|----------|-------------|---------|------------|
| 500 | $40.00 | $0.25 | $0.025 | $40.28 |
| 1,000 | $80.00 | $0.50 | $0.05 | $80.55 |
| 2,000 | $160.00 | $1.00 | $0.10 | $161.10 |
| 5,000 | $400.00 | $2.50 | $0.25 | $402.75 |
| 10,000 | $800.00 | $5.00 | $0.50 | $805.50 |

### Key Insights

1. **Linear Scaling**: Costs scale directly with document volume
2. **BDA Dominance**: Bedrock Data Automation represents 99%+ of total costs
3. **Minimal Infrastructure Overhead**: Lambda, S3, and SQS costs are negligible
4. **No Idle Costs**: Serverless architecture means you only pay for actual usage

## Cost Optimization Recommendations

### Immediate Actions

1. **Blueprint Field Optimization** ⚠️ **Critical for Cost Control**
   - **Current status**: 20 fields (safe zone, no additional charges)
   - **30-field threshold**: Adding 11+ more fields triggers $0.0005/field/page surcharge
   - **Cost impact**: Each additional field beyond 30 adds $1.00/month per 1,000 pages
   - **Recommendation**: Carefully evaluate any new field additions

2. **Validate Blueprint Complexity**
   - Review if all 20 current fields are necessary for your use case
   - Consider if some extractions could use standard processing ($0.01/page)
   - Test performance difference between custom vs standard processing

2. **Optimize Lambda Configuration**
   - Monitor actual execution times and adjust memory if needed
   - Consider ARM-based processors for 20% cost savings on Lambda
   - Implement batch processing for high-volume scenarios

3. **S3 Lifecycle Management**
   - Implement lifecycle policies for old resumes
   - Use S3 Intelligent Tiering for automatic cost optimization
   - Consider archiving processed results after 90 days

### Long-term Strategies

1. **Architecture Alternatives**
   - Evaluate if standard document processing meets requirements
   - Consider preprocessing to reduce BDA complexity
   - Implement caching for repeated processing patterns

2. **Hybrid Approach**
   - Use standard processing for simple resumes ($0.01/page = $20/month for 1,000 resumes)
   - Reserve custom blueprints for complex documents requiring structured extraction
   - Implement intelligent routing based on document complexity
   - **Potential savings**: Up to 75% cost reduction for documents suitable for standard processing

## Field Count Management Strategy

### Current Blueprint Analysis
Your blueprint is optimally designed with exactly **20 fields across 4 sections**:

| Section | Fields | Field Names |
|---------|--------|-------------|
| Personal Info | 5 | full_name, email, phone, address, linkedin |
| Educational Info | 5 | institution, degree, graduation_year, gpa, field_of_study |
| Experience | 5 | current_position, current_company, years_total, key_achievements, previous_roles |
| Skills | 5 | technical, soft, languages, certifications, tools |
| **Total** | **20** | **10 fields under the 30-field threshold** |

### Field Addition Cost Impact

| Total Fields | Cost per Page | Monthly Cost (2,000 pages) | Additional Cost |
|-------------|---------------|---------------------------|-----------------|
| 20 (current) | $0.0400 | $80.00 | Baseline |
| 25 | $0.0400 | $80.00 | $0.00 |
| 30 | $0.0400 | $80.00 | $0.00 |
| 31 | $0.0405 | $81.00 | +$1.00 |
| 35 | $0.0425 | $85.00 | +$5.00 |
| 40 | $0.0450 | $90.00 | +$10.00 |

### Recommendations for Future Enhancements

1. **Stay Under 30 Fields**: You have 10 fields of "free" expansion room
2. **Consolidate When Possible**: Consider combining related fields if you need more than 30
3. **Evaluate Field Necessity**: Each field beyond 30 costs $1/month per 1,000 pages processed
4. **Consider Standard Processing**: For simple extractions, standard processing is 75% cheaper

## Monitoring and Cost Control

### Recommended CloudWatch Alarms

```bash
# Monthly cost threshold alerts
aws cloudwatch put-metric-alarm \
  --alarm-name "BDA-Monthly-Cost-Alert" \
  --alarm-description "Alert when monthly BDA costs exceed $100" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold

# Daily processing volume alerts  
aws cloudwatch put-metric-alarm \
  --alarm-name "BDA-Daily-Volume-Alert" \
  --alarm-description "Alert when daily processing exceeds 50 documents" \
  --metric-name Invocations \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 86400 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold
```

### Cost Tracking Commands

```bash
# Monitor BDA costs
aws ce get-cost-and-usage \
  --time-period Start=2025-09-01,End=2025-09-30 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter file://bedrock-filter.json

# Lambda execution monitoring
aws logs tail /aws/lambda/BDAResumeStack-BDAProcessorFunction --follow

# S3 storage usage
aws s3api list-objects-v2 --bucket <bucket-name> \
  --query 'sum(Contents[].Size)' --output text
```

## Comparison with Previous Estimates

### Enhanced Analysis vs Original Report

**Original Report Issues:**
- Estimated BDA at $20.88/month total (significantly underestimated)
- Used generic document processing pricing ($0.01/page)
- Didn't account for custom blueprint premium (4x price difference)
- Missed the distinction between Standard vs Custom Output pricing

**Enhanced Analysis Benefits:**
- **Accurate BDA Pricing**: $0.040/page for custom blueprints (confirmed from AWS docs)
- **Field Count Analysis**: Verified 20 fields in blueprint (under 30-field threshold)
- **Real-time API Data**: Current pricing from AWS Pricing API
- **Architecture-aware**: Considers actual implementation with hierarchical schema
- **Pricing Examples**: Validated against AWS official pricing examples

### Key Differences

| Component | Original Estimate | Enhanced Estimate | Difference | Notes |
|-----------|------------------|-------------------|------------|-------|
| BDA Processing | ~$20 | $80.00 | +300% | Custom vs Standard pricing |
| Lambda | $0.50 | $0.50 | Same | Confirmed via API |
| S3 | $0.05 | $0.05 | Same | Confirmed via API |
| **Total** | **$20.88** | **$80.55** | **+286%** | **Primarily BDA underestimate** |

### Pricing Validation Examples

**Example 1 (matches your project):**
- Process 1,000 pages using custom blueprint with 20 fields
- Cost: 1,000 × $0.040 = $40.00
- Your project (2,000 pages): 2,000 × $0.040 = $80.00 ✅

**Example 2 (if you had >30 fields):**
- Blueprint with 35 fields = $0.040 + (5 × $0.0005) = $0.0425/page
- Your project would cost: 2,000 × $0.0425 = $85.00
- **Current cost advantage**: $5.00/month savings by staying under 30 fields

## Conclusion

This BDA resume parser project provides sophisticated hierarchical data extraction at a premium price point. The custom blueprint approach delivers superior structured output but comes with significantly higher costs than standard document processing.

### Key Takeaways

- **Primary Cost Driver**: Bedrock Data Automation custom processing ($80/month for 1,000 resumes)
- **Predictable Scaling**: Linear cost scaling with document volume
- **Minimal Infrastructure**: Supporting AWS services add <1% to total costs
- **No Idle Costs**: Serverless architecture ensures pay-per-use pricing

### Next Steps

1. **Validate Pricing**: Confirm custom blueprint pricing with AWS sales team
2. **Implement Monitoring**: Set up cost alerts and usage tracking
3. **Optimize Blueprint**: Review field extraction requirements for cost reduction

### Business Value Proposition

While the cost is higher than initially estimated, the project delivers:
- **Structured Data**: Hierarchical JSON output ready for downstream processing
- **High Accuracy**: Custom blueprints provide superior extraction quality
- **Real-time Processing**: Sub-second triggers with automatic scaling
- **Production Ready**: Complete infrastructure as code with monitoring

The premium pricing reflects the advanced AI capabilities and structured output quality that would be difficult and expensive to replicate with alternative solutions.