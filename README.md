# terraform-iona-ecs-service

A Terraform module for deploying ECS services or scheduled tasks on AWS. It creates a task definition, container definition, CloudWatch log groups, and — depending on `service_type` — either an ECS service with optional load balancing or an EventBridge-triggered scheduled task.

## Service Types

The `service_type` variable controls what kind of ECS workload is created:

| Value | Description |
|---|---|
| `service` (default) | A standard ECS service fronted by a single ALB target group. Creates the service, an IAM role for ECS, placement strategies, capacity provider strategy, app autoscaling, and a deployment monitor. |
| `service_multiple_load_balancers` | Same as `service` but accepts multiple target group ARNs via `multiple_target_group_arns`, allowing the service to register with more than one load balancer. |
| `service_no_load_balancer` | An ECS service with no load balancer attached. Useful for worker processes or consumers that don't receive inbound HTTP traffic. |
| `service_for_awsvpc_no_loadbalancer` | An ECS service using `awsvpc` network mode with no load balancer. Requires `network_configuration_subnets` and `network_configuration_security_groups`. |
| `scheduled_task` | No long-running service is created. Instead, an EventBridge rule triggers `ecs:RunTask` on a schedule. The ECS service, deployment monitor, and autoscaling resources are all skipped. Requires `schedule_expression`. |

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

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5.7 |
| aws | (any) |

## Modules

| Name | Source | Description |
|---|---|---|
| `service_container_definition` | `./container-definition` | Builds the ECS container definition JSON |
| `taskdef` | `./taskdef` | Creates the ECS task definition, task role, and execution role |
| `service` | `./service` | Creates the ECS service (skipped for `scheduled_task`) |
| `ecs_update_monitor` | `mergermarket/ecs-update-monitor/acuris` | Monitors ECS deployments (skipped for `scheduled_task`) |

## Resources

| Name | Type | Condition |
|---|---|---|
| `aws_cloudwatch_log_group.stdout` | resource | Always |
| `aws_cloudwatch_log_group.stderr` | resource | Always |
| `aws_cloudwatch_log_subscription_filter.kinesis_log_stdout_stream` | resource | When Datadog log subscription ARN is set and `add_datadog_feed` is true |
| `aws_cloudwatch_log_subscription_filter.kinesis_log_stderr_stream` | resource | Same as above |
| `aws_appautoscaling_target.ecs` | resource | Not `scheduled_task` |
| `aws_appautoscaling_scheduled_action.scale_down` | resource | Not `scheduled_task`, not live, `allow_overnight_scaledown` |
| `aws_appautoscaling_scheduled_action.scale_back_up` | resource | Same as above |
| `aws_appautoscaling_policy.task_scaling_policy` | resource | Not `scheduled_task`, `scaling_metrics` provided |
| `aws_cloudwatch_event_rule.scheduled_task` | resource | `scheduled_task` only |
| `aws_cloudwatch_event_target.scheduled_task` | resource | `scheduled_task` only |
| `aws_iam_role.scheduled_task_events` | resource | `scheduled_task` only |
| `aws_iam_role_policy.scheduled_task_events` | resource | `scheduled_task` only |
| `data.aws_ecs_cluster.cluster` | data | `scheduled_task` only |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `env` | Environment name | `string` | — | yes |
| `release` | Metadata about the release (`component`, `team`, `version`, `image_id`) | `map(string)` | — | yes |
| `cpu` | CPU unit reservation for the container | `string` | — | yes |
| `memory` | Memory reservation for the container in megabytes | `string` | — | yes |
| `service_type` | Type of ECS workload to create (see Service Types above) | `string` | `"service"` | no |
| `platform_config` | Platform configuration map | `map(string)` | `{}` | no |
| `secrets` | Secret credentials fetched using credstash | `map(string)` | `{}` | no |
| `common_application_environment` | Environment parameters passed to the container for all environments | `map(string)` | `{}` | no |
| `application_environment` | Environment-specific parameters passed to the container | `map(string)` | `{}` | no |
| `ecs_cluster` | The ECS cluster name | `string` | `"default"` | no |
| `port` | The port the container listens on. Not required for `scheduled_task`. | `string` | `"0"` | no |
| `privileged` | Give the container privileged access to the host | `bool` | `false` | no |
| `nofile_soft_ulimit` | Soft ulimit for number of open files | `string` | `"4096"` | no |
| `desired_count` | Number of task instances to keep running (services only) | `string` | `"3"` | no |
| `name_suffix` | Suffix appended to the service name for multiple services per component | `string` | `""` | no |
| `target_group_arn` | ALB target group ARN (for `service` type) | `string` | `""` | no |
| `multiple_target_group_arns` | Multiple ALB target group ARNs (for `service_multiple_load_balancers`) | `list(any)` | `[]` | no |
| `task_role_policy` | IAM policy document for the task role | `string` | sts:GetCallerIdentity | no |
| `assume_role_policy` | IAM assume role policy document | `string` | `""` | no |
| `taskdef_volume` | Map with `name` and `host_path` for a task definition volume | `map(string)` | `{}` | no |
| `container_mountpoint` | Map with `sourceVolume`, `containerPath`, and optional `readOnly` | `map(string)` | `{}` | no |
| `container_port_mappings` | JSON array of port mappings (overrides `port` if set) | `string` | `""` | no |
| `container_labels` | Additional Docker labels for the container | `map(string)` | `{}` | no |
| `deployment_minimum_healthy_percent` | Minimum healthy percent during deployments | `string` | `"100"` | no |
| `deployment_maximum_percent` | Maximum percent during deployments | `string` | `"200"` | no |
| `deployment_circuit_breaker` | Deployment circuit breaker configuration | `object({enable, rollback})` | `{enable=false, rollback=false}` | no |
| `deployment_timeout` | Timeout for deployment monitoring in seconds | `number` | `600` | no |
| `log_subscription_arn` | Kinesis stream ARN for log subscription | `string` | `""` | no |
| `add_datadog_feed` | Add subscription filter to CW log group for Datadog | `bool` | `true` | no |
| `allow_overnight_scaledown` | Allow service to scale down overnight (non-live only) | `bool` | `true` | no |
| `overnight_scaledown_min_count` | Minimum task count during overnight scaledown | `string` | `"0"` | no |
| `overnight_scaledown_start_hour` | Hour (UTC) to start overnight scaledown | `string` | `"22"` | no |
| `overnight_scaledown_end_hour` | Hour (UTC) to end overnight scaledown | `string` | `"06"` | no |
| `scaling_metrics` | List of scaling metric configurations for target tracking | `list(any)` | `[]` | no |
| `application_secrets` | Application secret names in AWS Secrets Manager | `list(string)` | `[]` | no |
| `platform_secrets` | Platform secret names in AWS Secrets Manager | `list(string)` | `[]` | no |
| `custom_secrets` | Arbitrary secret names in AWS Secrets Manager | `list(string)` | `[]` | no |
| `image_id` | ECR image ID (overrides `release["image_id"]` if set) | `string` | `""` | no |
| `network_mode` | Docker networking mode for the task | `string` | `"bridge"` | no |
| `network_configuration_subnets` | Subnets for `awsvpc` network mode | `list(any)` | `[]` | no |
| `network_configuration_security_groups` | Security groups for `awsvpc` network mode | `list(any)` | `[]` | no |
| `pack_and_distinct` | Enable binpacking and distinct-instance placement | `string` | `"false"` | no |
| `stop_timeout` | Seconds before container is forcefully killed (max 120) | `string` | `"120"` | no |
| `health_check_grace_period_seconds` | Grace period for load balancer health checks | `string` | `"0"` | no |
| `placement_constraint_on_demand_only` | Constrain tasks to on-demand instances only | `bool` | `false` | no |
| `extra_hosts` | Entries to add to `/etc/hosts` in the container | `list(object({hostname, ipAddress}))` | `[]` | no |
| `image_build_details` | Image build metadata (used for Graviton detection) | `map(string)` | `{buildx="false", platforms=""}` | no |
| `spot_capacity_percentage` | Percentage of tasks to run on spot instances | `number` | `33` | no |
| `log_configuration` | Custom log driver configuration | `object` | `null` | no |
| `firelens_configuration` | FireLens/Fluent Bit sidecar configuration | `object` | `null` | no |
| `is_test` | For testing only — disables AWS API calls for STS and cluster lookups | `bool` | `false` | no |
| `schedule_expression` | EventBridge schedule expression (required for `scheduled_task`), e.g. `rate(5 minutes)` or `cron(0 2 * * ? *)` | `string` | `""` | no |
| `schedule_task_count` | Number of task instances to launch per schedule trigger | `number` | `1` | no |
| `schedule_enabled` | Whether the EventBridge schedule rule is enabled | `bool` | `true` | no |

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
| `schedule_rule_arn` | ARN of the EventBridge rule (empty when not `scheduled_task`) |
| `schedule_rule_name` | Name of the EventBridge rule (empty when not `scheduled_task`) |

## Fluent Bit / FireLens Logging

This module supports logging through FireLens/Fluent Bit into Datadog via Kinesis Firehose. To enable it:

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

> **Important:** The S3 bucket containing the Fluent Bit config must have a name starting with `firelens` so that the execution role policy grants access.

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

