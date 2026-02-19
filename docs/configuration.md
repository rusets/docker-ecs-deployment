## Environment Variables / Parameters

| Name                  | Scope                | Description |
|-----------------------|----------------------|------------|
| `APP_PORT`            | ECS Task             | Port the Node.js application listens on (default: `80`) |
| `WAIT_MS`             | Wake Lambda          | Maximum wait time (ms) before redirecting to the task public IP |
| `CLUSTER_NAME`        | Wake / Auto-Sleep    | Target ECS cluster name |
| `SERVICE_NAME`        | Wake / Auto-Sleep    | Target ECS service name |
| `SLEEP_AFTER_MINUTES` | Auto-Sleep Lambda    | Idle timeout before scaling service back to `desiredCount=0` |
| `ECR_REPOSITORY`      | Terraform            | ECR repository storing the container image |
| `AWS_REGION`          | Global               | AWS region used across all components (default `us-east-1`) |
