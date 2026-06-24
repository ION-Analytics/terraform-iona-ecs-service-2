resource "aws_ecs_service" "service" {
  count = var.service_type == "service" ? 1 : 0

  name                               = var.name
  cluster                            = var.cluster
  task_definition                    = var.task_definition
  desired_count                      = var.desired_count
  iam_role                           = aws_iam_role.role.arn
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = true

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker["enable"]
    rollback = var.deployment_circuit_breaker["rollback"]
  }

  # Single container load balancer (original behavior)
  dynamic "load_balancer" {
    for_each = var.multiple_images ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # Multi-container load balancers
  dynamic "load_balancer" {
    for_each = var.multiple_images ? var.multi_container_load_balancers : []
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = lower(var.pack_and_distinct) == "true" ? "binpack" : "spread"
    field = lower(var.pack_and_distinct) == "true" ? "cpu" : "instanceId"
  }

  placement_constraints {
    type       = lower(var.pack_and_distinct) == "true" ? "distinctInstance" : "memberOf"
    expression = lower(var.pack_and_distinct) == "true" ? "" : "agentConnected == true"
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_providers
    content {
      base              = 0
      capacity_provider = capacity_provider_strategy.value["capacity_provider"]
      weight            = capacity_provider_strategy.value["weight"]
    }
  }

  force_new_deployment = true
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      ordered_placement_strategy,
    ]
  }
}

resource "aws_ecs_service" "service_multiple_loadbalancers" {
  count = var.service_type == "service_multiple_load_balancers" ? 1 : 0

  name                               = var.name
  cluster                            = var.cluster
  task_definition                    = var.task_definition
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = true

  # Single container, multiple target groups (original behavior)
  dynamic "load_balancer" {
    for_each = var.multiple_images ? [] : var.multiple_target_group_arns
    content {
      target_group_arn = load_balancer.value
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # Multi-container load balancers
  dynamic "load_balancer" {
    for_each = var.multiple_images ? var.multi_container_load_balancers : []
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker["enable"]
    rollback = var.deployment_circuit_breaker["rollback"]
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = lower(var.pack_and_distinct) == "true" ? "binpack" : "spread"
    field = lower(var.pack_and_distinct) == "true" ? "cpu" : "instanceId"
  }

  placement_constraints {
    type       = lower(var.pack_and_distinct) == "true" ? "distinctInstance" : "memberOf"
    expression = lower(var.pack_and_distinct) == "true" ? "" : "agentConnected == true"
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_providers
    content {
      base              = 0
      capacity_provider = capacity_provider_strategy.value["capacity_provider"]
      weight            = capacity_provider_strategy.value["weight"]
    }
  }

  force_new_deployment = true
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      ordered_placement_strategy,
    ]
  }
}

resource "aws_ecs_service" "service_no_loadbalancer" {
  count = var.service_type == "service_no_load_balancer" ? 1 : 0

  name                               = var.name
  cluster                            = var.cluster
  task_definition                    = var.task_definition
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = true

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker["enable"]
    rollback = var.deployment_circuit_breaker["rollback"]
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = lower(var.pack_and_distinct) == "true" ? "binpack" : "spread"
    field = lower(var.pack_and_distinct) == "true" ? "cpu" : "instanceId"
  }

  placement_constraints {
    type       = lower(var.pack_and_distinct) == "true" ? "distinctInstance" : "memberOf"
    expression = lower(var.pack_and_distinct) == "true" ? "" : "agentConnected == true"
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_providers
    content {
      base              = 0
      capacity_provider = capacity_provider_strategy.value["capacity_provider"]
      weight            = capacity_provider_strategy.value["weight"]
    }
  }

  force_new_deployment = true
  lifecycle {
    ignore_changes = [
      ordered_placement_strategy,
    ]
  }
}

resource "aws_ecs_service" "service_for_awsvpc_no_loadbalancer" {
  count = var.service_type == "service_for_awsvpc_no_loadbalancer" ? 1 : 0

  name                               = var.name
  cluster                            = var.cluster
  task_definition                    = var.task_definition
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  enable_execute_command             = true

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker["enable"]
    rollback = var.deployment_circuit_breaker["rollback"]
  }

  network_configuration {
    subnets         = var.network_configuration_subnets
    security_groups = var.network_configuration_security_groups
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = lower(var.pack_and_distinct) == "true" ? "binpack" : "spread"
    field = lower(var.pack_and_distinct) == "true" ? "cpu" : "instanceId"
  }

  placement_constraints {
    type       = lower(var.pack_and_distinct) == "true" ? "distinctInstance" : "memberOf"
    expression = lower(var.pack_and_distinct) == "true" ? "" : "agentConnected == true"
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_providers
    content {
      base              = 0
      capacity_provider = capacity_provider_strategy.value["capacity_provider"]
      weight            = capacity_provider_strategy.value["weight"]
    }
  }

  force_new_deployment = true
  lifecycle {
    ignore_changes = [
      capacity_provider_strategy,
      ordered_placement_strategy,
    ]
  }
}
