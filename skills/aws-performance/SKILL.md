---
name: aws-performance
description: AWS infrastructure performance and cost optimization — CloudWatch, auto-scaling, RDS tuning, S3, caching, cost controls
---

## AWS Performance & Cost Checklist

### CloudWatch & Monitoring

- [ ] Free tier metrics enabled for all services
- [ ] Custom metrics for application-level KPIs
- [ ] Detailed monitoring enabled for production EC2/RDS
- [ ] Alarms configured with SNS → Slack notifications
- [ ] Scale down on `INSUFFICIENT_DATA` and `ALARM` states
- [ ] Log retention policies set (don't keep logs forever)
- [ ] Dashboard for key metrics (CPU, memory, latency, error rates)

### RDS / Database

- [ ] Enhanced Monitoring enabled (OS-level metrics)
- [ ] Performance Insights enabled (query-level analysis)
- [ ] Connection pooling configured (max connections vs instance size)
- [ ] SSL enforced for all connections
- [ ] Read replicas for read-heavy workloads
- [ ] Automated backups with tested restore procedures
- [ ] Parameter group tuned (work_mem, shared_buffers, max_connections)
- [ ] Slow query logging enabled (> 1s threshold)
- [ ] Reserved instances for predictable workloads (40-60% savings)
- [ ] Right-sized instances — monitor CPU/memory utilization

### EC2 / Compute

- [ ] No static/elastic IPs where not needed
- [ ] Auto-scaling groups with proper scaling policies
- [ ] Single scaling trigger per dimension (CPU or request count, not both)
- [ ] Terminate protection on critical instances
- [ ] Reserved instances or Savings Plans for baseline capacity
- [ ] Spot instances for fault-tolerant batch workloads
- [ ] Right-sized instances — aim for 60-80% average utilization

### S3 / Storage

- [ ] Lifecycle policies for old data (→ Glacier after 90 days)
- [ ] Intelligent-Tiering for unpredictable access patterns
- [ ] CloudFront CDN for frequently accessed objects
- [ ] KMS encryption with customer-managed keys
- [ ] Versioning enabled on critical buckets
- [ ] Request metrics enabled for high-traffic buckets

### ELB / Networking

- [ ] Terminate SSL on load balancer (offload from app servers)
- [ ] Pre-warm for expected traffic spikes (contact AWS support)
- [ ] Health checks configured (HTTP path, not TCP)
- [ ] Cross-zone load balancing enabled
- [ ] Connection draining enabled for graceful deploys

### Caching Layers

- [ ] ElastiCache for session state and hot data
- [ ] Use configuration endpoints (not individual node addresses)
- [ ] CloudFront for static assets (CSS, JS, images)
- [ ] HTTP cache headers on API responses where appropriate
- [ ] Cache invalidation strategy documented

### WAF & Security

- [ ] Rate limiting rules on all public endpoints
- [ ] IP whitelisting for admin/internal endpoints
- [ ] Managed rule groups for common attack patterns (SQLi, XSS)
- [ ] Logging enabled with adequate retention
- [ ] Environment-specific rules (stricter in production)

### Cost Controls

- [ ] AWS Budgets with alerts at 50%, 80%, 100%
- [ ] Cost Explorer reviewed monthly
- [ ] Unused resources cleaned up (unattached EBS, old snapshots, idle NAT gateways)
- [ ] Right-sizing recommendations reviewed quarterly
- [ ] Tag everything — `environment`, `service`, `team`, `cost-center`
- [ ] Reserved capacity for predictable workloads

### General Best Practices

- [ ] Redundancy across at least 2 AZs
- [ ] Infrastructure as Code (Terraform) — no manual console changes
- [ ] Service limits documented and increased before hitting them
- [ ] Disaster recovery tested (at least annually)
- [ ] Deployment strategy: blue-green or rolling (zero downtime)

## Cost Optimization Quick Wins

| Action | Typical Savings | Effort |
|--------|----------------|--------|
| Reserved Instances (RDS/EC2) | 40-60% | Low |
| S3 Lifecycle policies | 30-50% on storage | Low |
| Right-size EC2 instances | 20-40% | Medium |
| Spot instances for batch | 60-90% | Medium |
| CloudFront for static assets | Reduced S3 requests | Low |
| Remove unused EBS volumes | Direct cost reduction | Low |
| Intelligent-Tiering S3 | Automatic savings | Low |

## AWS Performance Antipatterns

```
# BAD: Over-provisioned "just in case"
Instance: r5.4xlarge (128GB RAM)
Actual usage: 8GB average

# GOOD: Right-sized with auto-scaling
Instance: r5.large (16GB RAM) + auto-scaling policy
Scale out at 70% CPU, scale in at 30%
```

```
# BAD: Multiple scaling triggers competing
aws autoscaling put-scaling-policy --metric CPU --threshold 70
aws autoscaling put-scaling-policy --metric RequestCount --threshold 1000
# These fight each other!

# GOOD: Single primary metric per ASG
aws autoscaling put-scaling-policy --metric RequestCount --threshold 1000
```

## Recommended External Skills

```bash
# AWS cost optimization + monitoring (5 plugins with MCP servers)
/plugin marketplace add zxkane/aws-skills
/plugin install aws-cost-ops@aws-skills

# AWS cost scanner — 163 checks across 30+ services
# From: github.com/prajapatimehul/aws-cost-scanner
```
