variable "env" {
  description = "Environment name"
}

variable "platform_config" {
  description = "Platform configuration"
  type        = map(string)
  default     = {}
}

variable "release" {
  type        = map(string)
  description = "Metadata about the release"
}

variable "service_type" {
  type        = string
  description = "The type of service to create, e.g. service, service_multiple_load_balancers, service_no_load_balancer,service_for_awsvpc_no_loadbalancer"
  default     = "service"
}

variable "secrets" {
  type        = map(string)
  description = "Secret credentials fetched using credstash"
  default     = {}
}

variable "common_application_environment" {
  description = "Environment parameters passed to the container for all environments"
  type        = map(string)
  default     = {}
}

variable "application_environment" {
  description = "Environment specific parameters passed to the container"
  type        = map(string)
  default     = {}
}

variable "ecs_cluster" {
  type        = string
  description = "The ECS cluster"
  default     = "default"
}

variable "port" {
  type        = string
  description = "The port that container will be running on"
}

variable "cpu" {
  type        = string
  description = "CPU unit reservation for the container"
}

variable "privileged" {
  description = "Gives the container privileged access to the host"
  type        = bool
  default     = false
}

variable "memory" {
  type        = string
  description = "The memory reservation for the container in megabytes"
}

variable "nofile_soft_ulimit" {
  type        = string
  description = "The soft ulimit for the number of files in container"
  default     = "4096"
}

variable "desired_count" {
  description = "The number of instances of the task definition to place and keep running."
  type        = string
  default     = "3"
}

variable "name_suffix" {
  description = "Set a suffix that will be applied to the name in order that a component can have multiple services per environment"
  type        = string
  default     = ""
}

variable "target_group_arn" {
  description = "The ALB target group for the service."
  type        = string
  default     = ""
}

variable "multiple_target_group_arns" {
  description = "Mutiple target group ARNs to allow connection to multiple loadbalancers"
  type        = list(any)
  default     = []
}

variable "task_role_policy" {
  description = "IAM policy document to apply to the tasks via a task role"
  type        = string
  default = <<END
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:GetCallerIdentity",
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
END
}

variable "assume_role_policy" {
  description = "A valid IAM policy for assuming roles - optional"
  type        = string
  default     = ""
}

variable "taskdef_volume" {
  description = "Map containing 'name' and 'host_path' used to add a volume mapping to the taskdef."
  type        = map(string)
  default     = {}
}

variable "container_mountpoint" {
  description = "Map containing 'sourceVolume', 'containerPath' and 'readOnly' (optional) to map a volume into a container."
  type        = map(string)
  default     = {}
}

variable "container_port_mappings" {
  description = "JSON document containing an array of port mappings for the container defintion - if set port is ignored (optional)."
  default     = ""
  type        = string
}

variable "container_labels" {
  description = "Additional docker labels to apply to the container."
  type        = map(string)
  default     = {}
}

variable "deployment_minimum_healthy_percent" {
  description = "The minimumHealthyPercent represents a lower limit on the number of your service's tasks that must remain in the RUNNING state during a deployment, as a percentage of the desiredCount (rounded up to the nearest integer)."
  default     = "100"
}

variable "deployment_maximum_percent" {
  description = "The maximumPercent parameter represents an upper limit on the number of your service's tasks that are allowed in the RUNNING or PENDING state during a deployment, as a percentage of the desiredCount (rounded down to the nearest integer)."
  default     = "200"
}

variable "log_subscription_arn" {
  description = "To enable logging to a kinesis stream"
  default     = ""
}

variable "allow_overnight_scaledown" {
  description = "Allow service to be scaled down"
  default     = true
}

variable "overnight_scaledown_min_count" {
  description = "Minimum task count overnight"
  default     = "0"
}

variable "overnight_scaledown_start_hour" {
  description = "From when a service can be scaled down (Hour in UTC)"
  default     = "22"
}

variable "overnight_scaledown_end_hour" {
  description = "When to bring service back to full strength (Hour in UTC)"
  default     = "06"
}

variable "application_secrets" {
  description = "A list of application specific secret names that can be found in aws secrets manager"
  type        = list(string)
  default     = []
}

variable "platform_secrets" {
  description = "A list of common secret names for \"the platform\" that can be found in secrets manager"
  type        = list(string)
  default     = []
}

variable "custom_secrets" {
  description = "A list of arbitrary secret names that can be found in secrets manager"
  type        = list(string)
  default     = []
}

variable "is_test" {
  description = "For testing only. Stops the call to AWS for sts"
  default     = false
}

variable "image_id" {
  description = "ECR image_id for the ecs container"
  type        = string
  default     = ""
}

variable "network_mode" {
  description = "The Docker networking mode to use for the containers in the task"
  type        = string
  default     = "bridge"
}

variable "network_configuration_subnets" {
  description = "needed for network_mode awsvpc "
  type        = list(any)
  default     = []
}

variable "network_configuration_security_groups" {
  description = "needed for network_mode awsvpc "
  type        = list(any)
  default     = []
}

variable "add_datadog_feed" {
  description = "Flag to control adding subscription filter to CW loggroup"
  type        = bool
  default     = true
}

variable "pack_and_distinct" {
  description = "Enable distinct instance and task binpacking for better cluster utilisation. Enter 'true' for clusters with auto scaling groups. Enter 'false' for clusters with no ASG and instant counts less than or equal to desired tasks"
  type        = string
  default     = "false"
}

variable "stop_timeout" {
  description = "The duration is seconds to wait before the container is forcefully killed. Default 30s, max 120s."
  type        = string
  default     = "120"
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown, up to 2147483647. Default 0."
  type        = string
  default     = "0"
}

variable "deployment_timeout" {
  description = "Timeout to wait for the deployment to be finished [seconds]."
  type        = number
  default     = 600
}

variable "scaling_metrics" {
  description = "Allow service to be scaled down"
  type        = list(any)
  default     = []
}

variable "placement_constraint_on_demand_only" {
  description = "Add placement constraint to only run on on-demand instances"
  type        = bool
  default     = false
}

variable "extra_hosts" {
  description = "values to add to /etc/hosts in the container"
  type = list(object({
    hostname  = string
    ipAddress = string
  }))
  default = []
}

variable "image_build_details" {
  description = "Details of the image build"
  type        = map(string)
  default = {
    "buildx"    = "false",
    "platforms" = ""
  }
}

variable "spot_capacity_percentage" {
  default     = 33
  type        = number
  description = "Percentage of tasks to run on spot instances"
}

# https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html
variable "log_configuration" {
  type = object({
    logDriver = string
    options   = optional(map(string))
    secretOptions = optional(list(object({
      name      = string
      valueFrom = string
    })))
  })
  description = "Log configuration options to send to a custom log driver for the container. For more details, see https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_LogConfiguration.html"
  default     = null
}

# https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_FirelensConfiguration.html
variable "firelens_configuration" {
  type = object({
    options = optional(map(string))
    type    = string
  })
  description = "The FireLens configuration for the container. This is used to specify and configure a log router for container logs. For more details, see https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_FirelensConfiguration.html"
  default     = null
}

variable "deployment_circuit_breaker" {
  description = "Configuration block for deployment circuit breaker"
  type        = object({
    enable   = bool
    rollback = bool
  })
  default     = {
    enable   = false
    rollback = false
    }
}
