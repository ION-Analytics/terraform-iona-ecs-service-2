# Required parameters

variable "name" {
  description = "Name/name prefix to apply to the resources in the module."
  type        = string
}

variable "task_definition" {
  description = "The family and revision (family:revision) or full ARN of the task definition that you want to run in your service."
  type        = string
}

variable "target_group_arn" {
  description = "The target group ARN"
  type        = string
  default     = ""
}

variable "multiple_target_group_arns" {
  description = "Mutiple target group ARNs to allow connection to multiple loadbalancers"
  type        = list(any)
  default     = []
}

variable "service_type" {
  description = "Which of these 4 types of services are we creating? service (default) service_multiple_load_balancers, service_no_load_balancer, or service_for_awsvpc_no_loadbalancer"
  type        = string
  default     = "service"
}

variable "cluster" {
  description = "The name of the ECS cluster to deploy the service to."
  type        = string
  default     = "default"
}

variable "desired_count" {
  description = "The number of instances of the task definition to place and keep running."
  type        = string
  default     = "3"
}

variable "container_name" {
  description = "The name of the container to associate with the load balancer (as it appears in a container definition)."
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "The port on the container to associate with the load balancer."
  type        = string
  default     = "8000"
}

variable "deregistration_delay" {
  description = "The amount time for Elastic Load Balancing to wait before changing the state of a deregistering target from draining to unused. The range is 0-3600 seconds."
  type        = string
  default     = "10"
}

variable "health_check_interval" {
  description = "The approximate amount of time, in seconds, between health checks of an individual target. Minimum value 5 seconds, Maximum value 300 seconds."
  type        = string
  default     = "5"
}

variable "health_check_path" {
  description = "The destination for the health check request."
  type        = string
  default     = "/internal/healthcheck"
}

variable "health_check_timeout" {
  description = "The amount of time, in seconds, during which no response means a failed health check."
  type        = string
  default     = "4"
}

variable "health_check_healthy_threshold" {
  description = "The number of consecutive health checks successes required before considering an unhealthy target healthy."
  type        = string
  default     = "2"
}

variable "health_check_unhealthy_threshold" {
  description = "The number of consecutive health check failures required before considering the target unhealthy."
  type        = string
  default     = "2"
}

variable "health_check_matcher" {
  description = "The HTTP codes to use when checking for a successful response from a target. You can specify multiple values (for example, \"200,202\") or a range of values (for example, \"200-299\")."
  type        = string
  default     = "200-299"
}

variable "deployment_minimum_healthy_percent" {
  description = "The minimumHealthyPercent represents a lower limit on the number of your service's tasks that must remain in the RUNNING state during a deployment, as a percentage of the desiredCount (rounded up to the nearest integer)."
  default     = "100"
}

variable "deployment_maximum_percent" {
  description = "The maximumPercent parameter represents an upper limit on the number of your service's tasks that are allowed in the RUNNING or PENDING state during a deployment, as a percentage of the desiredCount (rounded down to the nearest integer)."
  default     = "200"
}

variable "pack_and_distinct" {
  description = "Enable distinct instance and task binpacking for better cluster utilisation. Enter 'true' for clusters with auto scaling groups. Enter 'false' for clusters with no ASG and instant counts less than or equal to desired tasks"
  type        = string
  default     = "false"
}

variable "deployment_circuit_breaker" {
  description = "Configuration block for deployment circuit breaker"
  type = object({
    enable   = bool
    rollback = bool
  })
  default = {
    enable   = false
    rollback = false
  }
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

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown, up to 2147483647. Default 0."
  type        = string
  default     = "0"
}

variable "capacity_providers" {
  description = "The capacity providers to add to the service. If the service is using the default capacity provider strategy, the service can also have one or more capacity providers specified using the capacityProviders parameter."
  type        = list(any)
  default     = []
}

variable "multiple_images" {
  description = "Flag indicating if this service uses multi-container task definitions"
  type        = bool
  default     = false
}

variable "multi_container_load_balancers" {
  description = "Load balancer configurations for multi-container tasks. List of objects with target_group_arn, container_name, and container_port."
  type = list(object({
    target_group_arn = string
    container_name   = string
    container_port   = number
  }))
  default = []
}
