# terraform-iona-ecs-service-2

**Fork of terraform-iona-ecs-service with sidecar container support**

A Terraform module for deploying ECS services or scheduled tasks on AWS. It creates a task definition, container definition, CloudWatch log groups, and — depending on `service_type` — either an ECS service with optional load balancing or an EventBridge-triggered scheduled task.

All service types support ECS Exec, capacity provider strategies (including Graviton and Spot), AWS Secrets Manager integration, and optional FireLens/Fluent Bit log routing.

## 🆕 What's New: Sidecar Container Support

This fork adds support for running a **second container** alongside your main application in the same ECS task. Perfect for:

- **Monitoring/Metrics**: Prometheus exporters, StatsD collectors
- **Logging**: Log shippers, aggregators  
- **Proxies**: Nginx, Envoy for traffic management
- **Security**: Vault agents, secrets managers
- **Service Mesh**: Linkerd, Istio sidecars

**100% backwards compatible** — existing configurations work unchanged. Simply add a `sidecar_container` block when needed.

See [Sidecar Container Usage](#sidecar-container-usage) below for examples and full documentation in [SIDECAR_CHANGES.md](./SIDECAR_CHANGES.md).

## Usage

### Standard service with ALB

```hcl
module "ecs_service" {
  source = "ION-Analytics/ecs-service/iona"

  env              = terraform.workspace
  ecs_cluster      = "my-cluster"
  release          = var.release
  image_id         = var.docker["image"]
  platform_config  = module.platform_config.config
  port             = "8080"
  cpu              = "256"
  memory           = "512"
  target_group_arn = aws_alb_target_group.service.arn
}
```

### Service with multiple load balancers

```hcl
module "ecs_service" {
  source = "ION-Analytics/ecs-service/iona"

  service_type               = "service_multiple_load_balancers"
  env                        = terraform.workspace
  ecs_cluster                = "my-cluster"
  release                    = var.release
  image_id                   = var.docker["image"]
  platform_config            = module.platform_config.config
  port                       = "8080"
  cpu                        = "256"
  memory                     = "512"
  multiple_target_group_arns = [aws_alb_target_group.primary.arn, aws_alb_target_group.secondary.arn]
}
```

### Service with no load balancer

```hcl
module "ecs_worker" {
  source = "ION-Analytics/ecs-service/iona"

  service_type    = "service_no_load_balancer"
  env             = terraform.workspace
  ecs_cluster     = "my-cluster"
  release         = var.release
  image_id        = var.docker["image"]
  platform_config = module.platform_config.config
  cpu             = "256"
  memory          = "512"
}
```

### Scheduled task

```hcl
module "ecs_scheduled_task" {
  source = "ION-Analytics/ecs-service/iona"

  service_type        = "scheduled_task"
  schedule_expression = "rate(5 minutes)"

  env             = terraform.workspace
  ecs_cluster     = "my-cluster"
  release         = var.release
  image_id        = var.docker["image"]
  platform_config = module.platform_config.config
  cpu             = "256"
  memory          = "512"
  # port is not required (defaults to "0")
}
```

### Service with sidecar container

```hcl
module "ecs_service_with_sidecar" {
  source = "ION-Analytics/ecs-service/iona"

  env              = terraform.workspace
  ecs_cluster      = "my-cluster"
  release          = var.release
  image_id         = var.docker["image"]
  platform_config  = module.platform_config.config
  port             = "8080"
  cpu              = "256"
  memory           = "512"
  target_group_arn = aws_alb_target_group.service.arn
  
  # Add a sidecar container for metrics export
  sidecar_container = {
    name   = "prometheus-exporter"
    image  = "prom/statsd-exporter:v0.26.0"
    cpu    = "128"
    memory = "256"
    port   = "9102"
    
    map_environment = {
      STATSD_LISTEN_UDP = "0.0.0.0:8125"
      PROM_LISTEN_HTTP  = "0.0.0.0:9102"
    }
  }
}
```

## Service Types

The `service_type` variable controls what kind of ECS workload is created:

| Value | Description |
|---|---|
| `service` (default) | A standard ECS service fronted by a single ALB target group. Creates the service, an IAM role for ECS, placement strategies, capacity provider strategy, app autoscaling, and a deployment monitor. |
| `service_multiple_load_balancers` | Same as `service` but accepts multiple target group ARNs via `multiple_target_group_arns`, allowing the service to register with more than one load balancer. |
| `service_no_load_balancer` | An ECS service with no load balancer attached. Useful for worker processes or consumers that don't receive inbound HTTP traffic. |
| `service_for_awsvpc_no_loadbalancer` | An ECS service using `awsvpc` network mode with no load balancer. Requires `network_configuration_subnets` and `network_configuration_security_groups`. |
| `scheduled_task` | No long-running service is created. Instead, an EventBridge rule triggers `ecs:RunTask` on a schedule. The ECS service, deployment monitor, and autoscaling resources are all skipped. Requires `schedule_expression`. |

## Sidecar Container Usage

### Overview

The `sidecar_container` variable allows you to run a second container alongside your main application container in the same ECS task. The sidecar automatically inherits most configuration from the main container (secrets, environment variables, timeouts, etc.) while allowing you to specify container-specific settings.

### Required Fields

| Name | Description | Type |
|---|---|---|
| `name` | Container name | `string` |
| `image` | Docker image | `string` |

### Optional Fields

| Name | Description | Type | Default |
|---|---|---|---|
| `cpu` | CPU units | `string` | Main container's CPU |
| `memory` | Memory in MB | `string` | Main container's memory |
| `port` | Single container port | `string` | `"0"` (no port) |
| `port_mappings` | Multiple port mappings (overrides `port`) | `list(object)` | Based on `port` |
| `privileged` | Run with elevated privileges | `bool` | `false` |
| `map_environment` | Additional environment variables | `map(string)` | `{}` |
| `mount_points` | Volume mounts | `list(object)` | Main container's mountpoint |
| `container_labels` | Docker labels | `map(string)` | `{}` |
| `log_configuration` | Custom log config | `object` | Main container's log config |

### Shared Configuration

The sidecar automatically inherits:
- All secrets (`application_secrets`, `platform_secrets`, `custom_secrets`)
- Environment variables (`common_application_environment`, `application_environment`, `secrets`)
- Timeouts (`stop_timeout`)
- Resource limits (`ulimits`)
- Host entries (`extra_hosts`)

### Logging

Each sidecar gets separate CloudWatch log groups:
- `${service_name}-${sidecar_name}-stdout`
- `${service_name}-${sidecar_name}-stderr`

### Examples

#### Metrics Exporter
```hcl
sidecar_container = {
  name   = "prometheus-exporter"
  image  = "prom/statsd-exporter:v0.26.0"
  cpu    = "128"
  memory = "256"
  port   = "9102"
}
```

#### Nginx Proxy
```hcl
sidecar_container = {
  name   = "nginx-proxy"
  image  = "nginx:latest"
  cpu    = "256"
  memory = "512"
  
  port_mappings = [
    { containerPort = 80 },
    { containerPort = 443 }
  ]
  
  mount_points = [
    {
      containerPath = "/etc/nginx/conf.d"
      sourceVolume  = "nginx-config"
      readOnly      = true
    }
  ]
}
```

For complete documentation, see [SIDECAR_CHANGES.md](./SIDECAR_CHANGES.md).

## Requirements

| Name | Version |
|---|---|
| [terraform](https://www.terraform.io/) | >= 1.5.7 |
| [aws](https://registry.terraform.io/providers/hashicorp/aws/latest) | >= 4.0 (no explicit constraint) |

## Providers

| Name | Description |
|---|---|
| `aws` | hashicorp/aws — used for all ECS, IAM, CloudWatch, EventBridge, and Secrets Manager resources |

## Modules

| Name | Source | Description |
|---|---|---|
| `service_container_definition` | `./container-definition` | Builds the ECS container definition JSON. Resolves application, platform, and custom secrets from AWS Secrets Manager. |
| `taskdef` | `./taskdef` | Creates the ECS task definition, task IAM role (with ECS Exec permissions), and task execution role. |
| `service` | `./service` | Creates the ECS service with placement strategies, capacity providers, and circuit breaker. Skipped when `service_type = "scheduled_task"`. |
| `ecs_update_monitor` | `mergermarket/ecs-update-monitor/acuris` v2.3.5 | Monitors ECS deployments and waits for stabilization. Skipped when `service_type = "scheduled_task"`. |

## Resources

### Always Created

| Name | Type |
|---|---|
| `aws_cloudwatch_log_group.stdout` | resource |
| `aws_cloudwatch_log_group.stderr` | resource |

### Conditional — Log Subscription

Created when `platform_config["datadog_log_subscription_arn"]` is set and `add_datadog_feed` is `true`:

| Name | Type |
|---|---|
| `aws_cloudwatch_log_subscription_filter.kinesis_log_stdout_stream` | resource |
| `aws_cloudwatch_log_subscription_filter.kinesis_log_stderr_stream` | resource |

### Conditional — Services Only (not `scheduled_task`)

| Name | Type | Additional Condition |
|---|---|---|
| `aws_appautoscaling_target.ecs` | resource | — |
| `aws_appautoscaling_scheduled_action.scale_down` | resource | `env != "live"` and `allow_overnight_scaledown` |
| `aws_appautoscaling_scheduled_action.scale_back_up` | resource | `env != "live"` and `allow_overnight_scaledown` |
| `aws_appautoscaling_policy.task_scaling_policy` | resource | `scaling_metrics` is non-empty |

### Conditional — Scheduled Tasks Only

Created when `service_type = "scheduled_task"`:

| Name | Type |
|---|---|
| `data.aws_ecs_cluster.cluster` | data source |
| `aws_iam_role.scheduled_task_events` | resource |
| `aws_iam_role_policy.scheduled_task_events` | resource |
| `aws_cloudwatch_event_rule.scheduled_task` | resource |
| `aws_cloudwatch_event_target.scheduled_task` | resource |

## Inputs

### Required

| Name | Description | Type |
|---|---|---|
| `env` | Environment name | `string` |
| `release` | Metadata about the release — must contain `component`, `team`, `version`, and `image_id` keys | `map(string)` |
| `cpu` | CPU unit reservation for the container | `string` |
| `memory` | Memory reservation for the container in megabytes | `string` |

### Service Configuration

| Name | Description | Type | Default |
|---|---|---|---|
| `service_type` | Type of ECS workload (see [Service Types](#service-types)) | `string` | `"service"` |
| `ecs_cluster` | The ECS cluster name | `string` | `"default"` |
| `desired_count` | Number of task instances to keep running (services only) | `string` | `"3"` |
| `name_suffix` | Suffix appended to the service name for multiple services per component | `string` | `""` |
| `port` | The port the container listens on (not required for `scheduled_task`) | `string` | `"0"` |

### Load Balancing

| Name | Description | Type | Default |
|---|---|---|---|
| `target_group_arn` | ALB target group ARN (for `service` type) | `string` | `""` |
| `multiple_target_group_arns` | Multiple ALB target group ARNs (for `service_multiple_load_balancers`) | `list(any)` | `[]` |
| `health_check_grace_period_seconds` | Grace period for load balancer health checks | `string` | `"0"` |

### Deployment

| Name | Description | Type | Default |
|---|---|---|---|
| `deployment_minimum_healthy_percent` | Minimum healthy percent during deployments | `string` | `"100"` |
| `deployment_maximum_percent` | Maximum percent during deployments | `string` | `"200"` |
| `deployment_circuit_breaker` | Deployment circuit breaker configuration | `object({enable=bool, rollback=bool})` | `{enable=false, rollback=false}` |
| `deployment_timeout` | Timeout for deployment monitoring in seconds | `number` | `600` |

### Container Configuration

| Name | Description | Type | Default |
|---|---|---|---|
| `image_id` | ECR image ID (overrides `release["image_id"]` if set) | `string` | `""` |
| `privileged` | Give the container privileged access to the host | `bool` | `false` |
| `nofile_soft_ulimit` | Soft ulimit for number of open files | `string` | `"4096"` |
| `stop_timeout` | Seconds before container is forcefully killed (max 120) | `string` | `"120"` |
| `container_labels` | Additional Docker labels for the container | `map(string)` | `{}` |
| `container_port_mappings` | JSON array of port mappings (overrides `port` if set) | `string` | `""` |
| `extra_hosts` | Entries to add to `/etc/hosts` in the container | `list(object({hostname, ipAddress}))` | `[]` |

### Environment & Secrets

| Name | Description | Type | Default |
|---|---|---|---|
| `platform_config` | Platform configuration map | `map(string)` | `{}` |
| `common_application_environment` | Environment parameters passed to the container for all environments | `map(string)` | `{}` |
| `application_environment` | Environment-specific parameters passed to the container | `map(string)` | `{}` |
| `secrets` | Secret credentials fetched using credstash | `map(string)` | `{}` |
| `application_secrets` | Application secret names in AWS Secrets Manager (resolved as `{team}/{env}/{component}/{name}`) | `list(string)` | `[]` |
| `platform_secrets` | Platform secret names in AWS Secrets Manager (resolved as `platform_secrets/{name}`) | `list(string)` | `[]` |
| `custom_secrets` | Arbitrary secret names in AWS Secrets Manager (full path) | `list(string)` | `[]` |

### Networking

| Name | Description | Type | Default |
|---|---|---|---|
| `network_mode` | Docker networking mode for the task | `string` | `"bridge"` |
| `network_configuration_subnets` | Subnets for `awsvpc` network mode | `list(any)` | `[]` |
| `network_configuration_security_groups` | Security groups for `awsvpc` network mode | `list(any)` | `[]` |

### IAM

| Name | Description | Type | Default |
|---|---|---|---|
| `task_role_policy` | IAM policy document for the task role | `string` | `sts:GetCallerIdentity` |
| `assume_role_policy` | IAM assume role policy document | `string` | `""` |

### Volumes

| Name | Description | Type | Default |
|---|---|---|---|
| `taskdef_volume` | Map with `name` and `host_path` for a task definition volume | `map(string)` | `{}` |
| `container_mountpoint` | Map with `sourceVolume`, `containerPath`, and optional `readOnly` | `map(string)` | `{}` |

### Placement & Capacity

| Name | Description | Type | Default |
|---|---|---|---|
| `pack_and_distinct` | Enable binpacking and distinct-instance placement | `string` | `"false"` |
| `placement_constraint_on_demand_only` | Constrain tasks to on-demand instances only | `bool` | `false` |
| `image_build_details` | Image build metadata (used for Graviton detection — requires `buildx=true` and `arm64` in `platforms`) | `map(string)` | `{buildx="false", platforms=""}` |
| `spot_capacity_percentage` | Percentage of tasks to run on spot instances | `number` | `33` |

### Logging

| Name | Description | Type | Default |
|---|---|---|---|
| `log_configuration` | Custom log driver configuration (see [FireLens](#firelens--fluent-bit-logging)) | `object({logDriver, options, secretOptions})` | `null` |
| `firelens_configuration` | FireLens/Fluent Bit sidecar configuration (see [FireLens](#firelens--fluent-bit-logging)) | `object({type, options})` | `null` |
| `add_datadog_feed` | Add subscription filter to CW log group for Datadog | `bool` | `true` |
| `log_subscription_arn` | Kinesis stream ARN for log subscription (unused — subscription uses `platform_config["datadog_log_subscription_arn"]`) | `string` | `""` |

### Autoscaling

| Name | Description | Type | Default |
|---|---|---|---|
| `scaling_metrics` | List of scaling metric configurations for target tracking | `list(any)` | `[]` |
| `allow_overnight_scaledown` | Allow service to scale down overnight (non-live only) | `bool` | `true` |
| `overnight_scaledown_min_count` | Minimum task count during overnight scaledown | `string` | `"0"` |
| `overnight_scaledown_start_hour` | Hour (UTC) to start overnight scaledown | `string` | `"22"` |
| `overnight_scaledown_end_hour` | Hour (UTC) to end overnight scaledown | `string` | `"06"` |

### Scheduled Task

| Name | Description | Type | Default |
|---|---|---|---|
| `schedule_expression` | EventBridge schedule expression (required for `scheduled_task`), e.g. `rate(5 minutes)` or `cron(0 2 * * ? *)` | `string` | `""` |
| `schedule_task_count` | Number of task instances to launch per schedule trigger | `number` | `1` |
| `schedule_enabled` | Whether the EventBridge schedule rule is enabled | `bool` | `true` |

### Sidecar Container

| Name | Description | Type | Default |
|---|---|---|---|
| `sidecar_container` | Optional sidecar container configuration (see [Sidecar Container Usage](#sidecar-container-usage)) | `object` | `null` |

### Testing

| Name | Description | Type | Default |
|---|---|---|---|
| `is_test` | For testing only — disables AWS API calls for STS and cluster lookups | `bool` | `false` |

## Outputs

| Name | Description |
|---|---|
| `task_role_arn` | ARN of the ECS task IAM role |
| `task_role_name` | Name of the ECS task IAM role |
| `taskdef_arn` | ARN of the ECS task definition |
| `stdout_name` | CloudWatch log group name for stdout |
| `stderr_name` | CloudWatch log group name for stderr |
| `full_service_name` | Full computed service name (`{env}-{component}{suffix}`) |
| `use_graviton` | Whether Graviton capacity providers are in use |
| `capacity_providers` | List of capacity provider strategy objects |
| `schedule_rule_arn` | ARN of the EventBridge rule (empty string when not `scheduled_task`) |
| `schedule_rule_name` | Name of the EventBridge rule (empty string when not `scheduled_task`) |
| `sidecar_stdout_name` | CloudWatch log group name for sidecar stdout (empty if no sidecar) |
| `sidecar_stderr_name` | CloudWatch log group name for sidecar stderr (empty if no sidecar) |
| `sidecar_container_name` | Name of the sidecar container (empty if no sidecar) |

## Capacity Provider Strategy

The module automatically selects capacity providers based on the ECS cluster name and image build details:

- **Graviton** providers are used when `image_build_details["buildx"] == "true"` and the `platforms` value contains `arm64`.
- **Spot vs On-Demand** weighting is controlled by `spot_capacity_percentage` (default `33`). The module computes integer weights for the on-demand and spot capacity providers accordingly.

Capacity provider names follow the pattern `{cluster}-native-scaling[-graviton][-spot]`.

## Overnight Scaledown

For non-`live` environments, services can be automatically scaled down overnight to reduce costs:

- Enabled by default (`allow_overnight_scaledown = true`)
- Scales to `overnight_scaledown_min_count` (default `0`) tasks between `overnight_scaledown_start_hour` (default `22` UTC) and `overnight_scaledown_end_hour` (default `06` UTC)
- Scale-back-up runs at the end hour on weekdays only (Mon–Fri)

Set `allow_overnight_scaledown = false` to disable.

## FireLens / Fluent Bit Logging

This module supports logging through FireLens/Fluent Bit (e.g. into Datadog via Kinesis Firehose). To enable it:

1. Override `log_configuration` to use the `awsfirelens` log driver:

```hcl
log_configuration = {
  logDriver = "awsfirelens"
  options = {
    Name            = "firehose"
    region          = "us-west-2"
    delivery_stream = "DatadogFirehoseStream"
  }
}
```

2. Provide a `firelens_configuration` to enable the sidecar container:

```hcl
firelens_configuration = {
  type = "fluentbit"
  options = {
    enable-ecs-log-metadata = "true"
    config-file-type        = "s3"
    config-file-value       = aws_s3_object.fluentbit_config.arn
  }
}
```

> **Important:** If you set `log_configuration` to `awsfirelens` without also providing `firelens_configuration`, your service will fail to start.

> **Important:** The S3 bucket containing the Fluent Bit config must have a name starting with `firelens` so that the task execution role policy grants access.

The sidecar container is named `log_router_{component}{suffix}` and uses `public.ecr.aws/aws-observability/aws-for-fluent-bit:stable`.

The contents of that file can be defined with a simple HEREDOC variable such as:

```
locals{
  fluentbit_config = <<-EOF
[FILTER]
    name                  multiline
    match                 *
    multiline.key_content log
    multiline.parser      go
EOF
}
```

## Other things you can do:

# remove lines from the log via regex

Useful for services behind a load balancer. The load balancer will periodically ping the service and generate a web access entry. If you are logging those, they can get to be a bit much (about 1 every second) 

You can prevent those from leaving the sidecar with this config:

```
[FILTER]
    Name    grep
    Match   *
    Exclude log ELB-HealthChecker/2.0
```

This tells fluentbit to use the grep filter (https://docs.fluentbit.io/manual/data-pipeline/filters/grep) and evaluate every entry that comes through. If the "log" field contains "ELB-HealthChecker/2.0" the entry will be silently discarded

You can find more about configuring Fluent-bit here: https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/classic-mode/configuration-file

## terraform-iona-log-config

In order to standardize our use of these logging services, I've created the following repo/module: https://github.com/ION-Analytics/terraform-iona-log-config You're welcome to use this, but it may be tailored too specifically to Backstop's needs.

