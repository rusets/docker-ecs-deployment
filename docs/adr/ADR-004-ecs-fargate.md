# ADR-004: Choosing AWS ECS Fargate for Compute

## Status
Accepted

## Context
The service consists of a single Node.js container.
Requirements:
- Zero cost when idle
- Automatic wake/sleep behavior
- Fully reproducible `terraform apply/destroy`
- Minimal operations overhead

Considered options:
- ECS on EC2
- Docker on EC2
- Custom EC2 instance
- ECS Fargate

## Decision
Use **ECS Fargate** (serverless containers).

## Rationale
- **True zero-cost idle** when desiredCount = 0  
- Fast container startup (20–40 sec)
- No servers, patching, or AMIs
- Simplified IAM (executionRole + taskRole)
- Ideal for wake/sleep architectures
- No networking complexity (awsvpc + public ENI)
- Clean and compact Terraform footprint

## Why not EC2-based compute
- EC2 incurs cost even when idle
- Wake/sleep requires full VM bootstrap/teardown
- Requires OS patching and maintenance
- Slower cold start
- Opposes the project’s goal: *ultra-low-cost + simplicity*

## Consequences
- No host-level customization (daemon processes, privileged mode)
- No daemon-like tasks except via Fargate scheduled tasks
- Perfect fit for a single-service backend with predictable traffic