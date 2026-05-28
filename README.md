# terraform-iona-ecs-service

An ECS service with an ALB target group, suitable for routing to from an ALB.

This repo consolidates the following repos:
* https://github.com/mergermarket/terraform-acuris-ecs-service
* https://github.com/mergermarket/terraform-acuris-load-balanced-ecs-service-no-target-group
* https://github.com/mergermarket/terraform-acuris-task-definition-with-task-role
* https://github.com/mergermarket/terraform-acuris-ecs-container-definition

The "ecs-service-no-target-group" used a series of "if-then" statements to determine which "type" of ecs service to create. Because this required some values to be known before the module ran, it was impossible to create the ecs service and the corresponding target group at the same time. To get around that, we use a new variable named service_type that can be one of the following values:
* service
* service_multiple_load_balancers
* service_no_load_balancer
* service_for_awsvpc_no_loadbalancer

I've only ever used the first of these, so I'm unsire what the others are for, but they are included for completeness


# Fluent-bit logs

This repo now allows logging through Firelens/Fluent-bit into Datadog.

You can now override the log_configuration variable and pass an optional firelens_configuration variable that will configure the sidecar and fluentbit process. The firehose delivery stream must have already been setup outside of this module.

```
  log_configuration = {
    logDriver = "awsfirelens"
    options = {
      Name = "firehose"
      region = module.platform_config.config["region"]
      delivery_stream = "DatadogFirehoseStream"
    }
  }
```
To enable the firelens sidecar, you MUST provide a firelens_configuration variable. If you do not provide that variable, the logs will flow to cloudwatch and datadog as usual AS LONG AS you don't override the log_configuration. If you override the log_configuration in the above fashion but do not provide a firelens_configuration, ***your services will break***.

The sidecar is named `log_router_${var.release["component"]}${var.name_suffix}` and is sourced from `public.ecr.aws/aws-observability/aws-for-fluent-bit:stable`

The sidecar gets its firelens configuration directly from the variable. You could specify something other than "fluentbit" for the type, but this module won't understand what to do with it and you'll likely end up with a broken service. These options are the only ones availble and you will probably want them as the default fluentbit config doesn't do much. This modue does not create the s3 object, the calling module should do that.

The s3 object you pass for the config-file-value should be a valid fluentbit configuration snippet that will be imported into the fluentbit configuration.

***The s3 bucket that object is sourced from should start with the phrase 'firelens' so that the permissions will be applied properly to the ECS Role***

```
  firelens_configuration = {
    type = "fluentbit"
    options = {
      enable-ecs-log-metadata = "true"
      config-file-type =  "s3",
      config-file-value = aws_s3_object.fluentbit_config.arn
    }
  }
```

The default Fluent-bit config looks like this:

```
[INPUT]
    Name forward
    Mem_Buf_Limit 25MB
    unix_path /var/run/fluent.sock

[INPUT]
    Name forward
    Listen 0.0.0.0
    Port 24224

[INPUT]
    Name tcp
    Tag firelens-healthcheck
    Listen 127.0.0.1
    Port 8877

[FILTER]
    Name record_modifier
    Match *
    Record ec2_instance_id i-0d1a7bebd0e42bc04
    Record ecs_cluster or1-test
    Record ecs_task_arn arn:aws:ecs:us-west-2:254076036999:task/or1-test/a87638ce0fa0408ba98d11d70dbc66b8
    Record ecs_task_definition or1-test-cdflow-log-testing:37

[OUTPUT]
    Name null
    Match firelens-healthcheck

[OUTPUT]
    Name firehose
    Match cdflow-log-testing-firelens*
    delivery_stream DatadogFirehoseStream
    region us-west-2
```

These are all either defaults or items set up by the ECS task definition. 

When you use an external configuration file, this gets added to the config:
```
@INCLUDE /fluent-bit/etc/external.conf
```

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


<!-- BEGIN_TF_DOCS -->
## Requirements

| Name                                                                      | Version  |
|---------------------------------------------------------------------------|----------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |

## Providers

| Name                                              | Version |
|---------------------------------------------------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a     |

## Modules

| Name                                                                                                                         | Source                                                        | Version |
|------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|---------|
| <a name="module_ecs_update_monitor"></a> [ecs\_update\_monitor](#module\_ecs\_update\_monitor)                               | mergermarket/ecs-update-monitor/acuris                        | 2.3.5   |

## Resources

| Name                                                                                                                                                                               | Type     |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|
| [aws_appautoscaling_policy.task_scaling_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy)                                 | resource |
| [aws_appautoscaling_scheduled_action.scale_back_up](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_scheduled_action)                   | resource |
| [aws_appautoscaling_scheduled_action.scale_down](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_scheduled_action)                      | resource |
| [aws_appautoscaling_target.ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target)                                                 | resource |
| [aws_cloudwatch_log_group.stderr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group)                                                | resource |
| [aws_cloudwatch_log_group.stdout](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group)                                                | resource |
| [aws_cloudwatch_log_subscription_filter.kinesis_log_stderr_stream](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_subscription_filter) | resource |
| [aws_cloudwatch_log_subscription_filter.kinesis_log_stdout_stream](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_subscription_filter) | resource |

## Inputs

| Name                                                                                                                                                    | Description                                                                                                                                                                                                                                   | Type                                                    | Default                                                                                                                                                                                  | Required |
|---------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:--------:|
| <a name="input_add_datadog_feed"></a> [add\_datadog\_feed](#input\_add\_datadog\_feed)                                                                  | Flag to control adding subscription filter to CW loggroup                                                                                                                                                                                     | `bool`                                                  | `true`                                                                                                                                                                                   |    no    |
| <a name="input_allow_overnight_scaledown"></a> [allow\_overnight\_scaledown](#input\_allow\_overnight\_scaledown)                                       | Allow service to be scaled down                                                                                                                                                                                                               | `bool`                                                  | `true`                                                                                                                                                                                   |    no    |
| <a name="input_application_environment"></a> [application\_environment](#input\_application\_environment)                                               | Environment specific parameters passed to the container                                                                                                                                                                                       | `map(string)`                                           | `{}`                                                                                                                                                                                     |    no    |
| <a name="input_application_secrets"></a> [application\_secrets](#input\_application\_secrets)                                                           | A list of application specific secret names that can be found in aws secrets manager                                                                                                                                                          | `list(string)`                                          | `[]`                                                                                                                                                                                     |    no    |
| <a name="input_assume_role_policy"></a> [assume\_role\_policy](#input\_assume\_role\_policy)                                                            | A valid IAM policy for assuming roles - optional                                                                                                                                                                                              | `string`                                                | `""`                                                                                                                                                                                     |    no    |
| <a name="input_common_application_environment"></a> [common\_application\_environment](#input\_common\_application\_environment)                        | Environment parameters passed to the container for all environments                                                                                                                                                                           | `map(string)`                                           | `{}`                                                                                                                                                                                     |    no    |
| <a name="input_container_labels"></a> [container\_labels](#input\_container\_labels)                                                                    | Additional docker labels to apply to the container.                                                                                                                                                                                           | `map(string)`                                           | `{}`                                                                                                                                                                                     |    no    |
| <a name="input_container_mountpoint"></a> [container\_mountpoint](#input\_container\_mountpoint)                                                        | Map containing 'sourceVolume', 'containerPath' and 'readOnly' (optional) to map a volume into a container.                                                                                                                                    | `map(string)`                                           | `{}`                                                                                                                                                                                     |    no    |
| <a name="input_container_port_mappings"></a> [container\_port\_mappings](#input\_container\_port\_mappings)                                             | JSON document containing an array of port mappings for the container defintion - if set port is ignored (optional).                                                                                                                           | `string`                                                | `""`                                                                                                                                                                                     |    no    |
| <a name="input_cpu"></a> [cpu](#input\_cpu)                                                                                                             | CPU unit reservation for the container                                                                                                                                                                                                        | `string`                                                | n/a                                                                                                                                                                                      |   yes    |
| <a name="input_deployment_maximum_percent"></a> [deployment\_maximum\_percent](#input\_deployment\_maximum\_percent)                                    | The maximumPercent parameter represents an upper limit on the number of your service's tasks that are allowed in the RUNNING or PENDING state during a deployment, as a percentage of the desiredCount (rounded down to the nearest integer). | `string`                                                | `"200"`                                                                                                                                                                                  |    no    |
| <a name="input_deployment_minimum_healthy_percent"></a> [deployment\_minimum\_healthy\_percent](#input\_deployment\_minimum\_healthy\_percent)          | The minimumHealthyPercent represents a lower limit on the number of your service's tasks that must remain in the RUNNING state during a deployment, as a percentage of the desiredCount (rounded up to the nearest integer).                  | `string`                                                | `"100"`                                                                                                                                                                                  |    no    |
| <a name="input_deployment_timeout"></a> [deployment\_timeout](#input\_deployment\_timeout)                                                              | Timeout to wait for the deployment to be finished [seconds].                                                                                                                                                                                  | `number`                                                | `600`                                                                                                                                                                                    |    no    |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count)                                                                             | The number of instances of the task definition to place and keep running.                                                                                                                                                                     | `string`                                                | `"3"`                                                                                                                                                                                    |    no    |
| <a name="input_ecs_cluster"></a> [ecs\_cluster](#input\_ecs\_cluster)                                                                                   | The ECS cluster                                                                                                                                                                                                                               | `string`                                                | `"default"`                                                                                                                                                                              |    no    |
| <a name="input_env"></a> [env](#input\_env)                                                                                                             | Environment name                                                                                                                                                                                                                              | `any`                                                   | n/a                                                                                                                                                                                      |   yes    |
| <a name="input_extra_hosts"></a>[extra\_hosts](#input\_extra\_hosts)                                                                                    | List of objects containing 'hostname' and 'ipAddress' used to add extra /etc/hosts to the container.                                                                                                                                          | `list(object({'hostname': string 'ipAddress': string})` | `[]`                                                                                                                                                                                     |    no    |
| <a name="input_health_check_grace_period_seconds"></a> [health\_check\_grace\_period\_seconds](#input\_health\_check\_grace\_period\_seconds)           | Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown, up to 2147483647. Default 0.                                                                                                 | `string`                                                | `"0"`                                                                                                                                                                                    |    no    |
| <a name="input_image_id"></a> [image\_id](#input\_image\_id)                                                                                            | ECR image\_id for the ecs container                                                                                                                                                                                                           | `string`                                                | `""`                                                                                                                                                                                     |    no    |
| <a name="input_is_test"></a> [is\_test](#input\_is\_test)                                                                                               | For testing only. Stops the call to AWS for sts                                                                                                                                                                                               | `bool`                                                  | `false`                                                                                                                                                                                  |    no    |
| <a name="input_log_subscription_arn"></a> [log\_subscription\_arn](#input\_log\_subscription\_arn)                                                      | To enable logging to a kinesis stream                                                                                                                                                                                                         | `string`                                                | `""`                                                                                                                                                                                     |    no    |
| <a name="input_memory"></a> [memory](#input\_memory)                                                                                                    | The memory reservation for the container in megabytes                                                                                                                                                                                         | `string`                                                | n/a                                                                                                                                                                                      |   yes    |
| <a name="input_multiple_target_group_arns"></a> [multiple\_target\_group\_arns](#input\_multiple\_target\_group\_arns)                                  | Mutiple target group ARNs to allow connection to multiple loadbalancers                                                                                                                                                                       | `list(any)`                                             | `[]`                                                                                                                                                                                     |    no    |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix)                                                                                   | Set a suffix that will be applied to the name in order that a component can have multiple services per environment                                                                                                                            | `string`                                                | `""`                                                                                                                                                                                     |    no    |
| <a name="input_network_configuration_security_groups"></a> [network\_configuration\_security\_groups](#input\_network\_configuration\_security\_groups) | needed for network\_mode awsvpc                                                                                                                                                                                                               | `list(any)`                                             | `[]`                                                                                                                                                                                     |    no    |
| <a name="input_network_configuration_subnets"></a> [network\_configuration\_subnets](#input\_network\_configuration\_subnets)                           | needed for network\_mode awsvpc                                                                                                                                                                                                               | `list(any)`                                             | `[]`                                                                                                                                                                                     |    no    |
| <a name="input_network_mode"></a> [network\_mode](#input\_network\_mode)                                                                                | The Docker networking mode to use for the containers in the task                                                                                                                                                                              | `string`                                                | `"bridge"`                                                                                                                                                                               |    no    |
| <a name="input_nofile_soft_ulimit"></a> [nofile\_soft\_ulimit](#input\_nofile\_soft\_ulimit)                                                            | The soft ulimit for the number of files in container                                                                                                                                                                                          | `string`                                                | `"4096"`                                                                                                                                                                                 |    no    |
| <a name="input_overnight_scaledown_end_hour"></a> [overnight\_scaledown\_end\_hour](#input\_overnight\_scaledown\_end\_hour)                            | When to bring service back to full strength (Hour in UTC)                                                                                                                                                                                     | `string`                                                | `"06"`                                                                                                                                                                                   |    no    |
| <a name="input_overnight_scaledown_min_count"></a> [overnight\_scaledown\_min\_count](#input\_overnight\_scaledown\_min\_count)                         | Minimum task count overnight                                                                                                                                                                                                                  | `string`                                                | `"0"`                                                                                                                                                                                    |    no    |
| <a name="input_overnight_scaledown_start_hour"></a> [overnight\_scaledown\_start\_hour](#input\_overnight\_scaledown\_start\_hour)                      | From when a service can be scaled down (Hour in UTC)                                                                                                                                                                                          | `string`                                                | `"22"`                                                                                                                                                                                   |    no    |
| <a name="input_pack_and_distinct"></a> [pack\_and\_distinct](#input\_pack\_and\_distinct)                                                               | Enable distinct instance and task binpacking for better cluster utilisation. Enter 'true' for clusters with auto scaling groups. Enter 'false' for clusters with no ASG and instant counts less than or equal to desired tasks                | `string`                                                | `"false"`                                                                                                                                                                                |    no    |
| <a name="input_platform_config"></a> [platform\_config](#input\_platform\_config)                                                                       | Platform configuration                                                                                                                                                                                                                        | `map(string)`                                           | `{}`                                                                                                                                                                                     |    no    |
| <a name="input_platform_secrets"></a> [platform\_secrets](#input\_platform\_secrets)                                                                    | A list of common secret names for "the platform" that can be found in secrets manager                                                                                                                                                         | `list(string)`                                          | `[]`                                                                                                                                                                                     |    no    |
| <a name="input_custom_secrets"></a> [custom\_secrets](#input\_custom\_secrets)                                                                    | A list of secret names that can be referenced by multiple services                                                                                                                                                        | `list(string)`                                          | `[]`                                                                                                                                                                                     |    no    |
| <a name="input_port"></a> [port](#input\_port)                                                                                                          | The port that container will be running on                                                                                                                                                                                                    | `string`                                                | n/a                                                                                                                                                                                      |   yes    |
| <a name="input_privileged"></a> [privileged](#input\_privileged)                                                                                        | Gives the container privileged access to the host                                                                                                                                                                                             | `bool`                                                  | `false`                                                                                                                                                                                  |    no    |
| <a name="input_release"></a> [release](#input\_release)                                                                                                 | Metadata about the release                                                                                                                                                                                                                    | `map(string)`                                           | n/a                                                                                                                                                                                      |   yes    |
| <a name="input_scaling_metrics"></a> [scaling\_metrics](#input\_scaling\_metrics)                                                                       | A list of maps defining the scaling of the services tasks - for more info see below                                                                                                                                                           | `list(any)`                                             | `[]`                                                                                                                                                                                     |    no    |
| <a name="input_secrets"></a> [secrets](#input\_secrets)                                                                                                 | Secret credentials fetched using credstash                                                                                                                                                                                                    | `map(string)`                                           | `{}`                                                                                                                                                                                     |    no    |
| <a name="input_stop_timeout"></a> [stop\_timeout](#input\_stop\_timeout)                                                                                | The duration is seconds to wait before the container is forcefully killed. Default 30s, max 120s.                                                                                                                                             | `string`                                                | `"none"`                                                                                                                                                                                 |    no    |
| <a name="input_target_group_arn"></a> [target\_group\_arn](#input\_target\_group\_arn)                                                                  | The ALB target group for the service.                                                                                                                                                                                                         | `string`                                                | `""`                                                                                                                                                                                     |    no    |
| <a name="input_task_role_policy"></a> [task\_role\_policy](#input\_task\_role\_policy)                                                                  | IAM policy document to apply to the tasks via a task role                                                                                                                                                                                     | `string`                                                | `"{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Action\": \"sts:GetCallerIdentity\",\n      \"Effect\": \"Allow\",\n      \"Resource\": \"*\"\n    }\n  ]\n}\n"` |    no    |
| <a name="input_taskdef_volume"></a> [taskdef\_volume](#input\_taskdef\_volume)                                                                          | Map containing 'name' and 'host\_path' used to add a volume mapping to the taskdef.                                                                                                                                                           | `map(string)`                                           | `{}`                                                                                                                                                                                     |    no    |
## Outputs

| Name                                                                                        | Description |
|---------------------------------------------------------------------------------------------|-------------|
| <a name="output_full_service_name"></a> [full\_service\_name](#output\_full\_service\_name) | n/a         |
| <a name="output_stderr_name"></a> [stderr\_name](#output\_stderr\_name)                     | n/a         |
| <a name="output_stdout_name"></a> [stdout\_name](#output\_stdout\_name)                     | n/a         |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn)             | n/a         |
| <a name="output_task_role_name"></a> [task\_role\_name](#output\_task\_role\_name)          | n/a         |
| <a name="output_taskdef_arn"></a> [taskdef\_arn](#output\_taskdef\_arn)                     | n/a         |

## Scaling Metrics

Setting this variable to a lis tof maps.  Each map defines a seperate scaling policy

| Param              | Description                                                                                                                                                                                        |
|--------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| name               | (Required) Must be unique                                                                                                                                                                          |
| metric             | (Required) Name of the metric to use for scaling - see below for allowed values                                                                                                                    |
| target_value       | (Required) Value of the above metric that scaling will maintain                                                                                                                                    |
| disable_scale_in   | (Optional) Whether scale in by the target tracking policy is disabled. If the value is true, scale in is disabled and the target tracking policy won't remove capacity from the scalable resource. |
| scale_in_cooldown  | (Optional) Amount of time, in seconds, after a scale in activity completes before another scale in activity can start                                                                              |
| scale_out_cooldown | (Optional) Amount of time, in seconds, after a scale out activity completes before another scale out activity can start.                                                                           |

### Allowed Metrics
* ECSServiceAverageCPUUtilization
* ECSServiceAverageMemoryUtilization
* ALBRequestCountPerTarget

### Example
```
  scaling_metrics = [
    {
      name               = "cpu"
      metric             = "ECSServiceAverageCPUUtilization"
      target_value       = 10
      disable_scale_in   = false
      scale_in_cooldown  = 180
      scale_out_cooldown = 90
    },
    {
      name               = "memory"
      metric             = "ECSServiceAverageMemoryUtilization"
      target_value       = 10
      disable_scale_in   = false
      scale_in_cooldown  = 180
      scale_out_cooldown = 90
    }
  ]
```
<!-- END_TF_DOCS -->
