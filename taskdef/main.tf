locals {
  team      = lookup(var.release, "team", "")
  component = lookup(var.release, "component", "")
  account_id = element(
    concat(data.aws_caller_identity.current.*.account_id, [""]),
    0,
  )

  name_prefix = length(var.family) <= 32 ? var.family : format("%.24stf%.4s", var.family, sha1(var.family))
}

resource "aws_ecs_task_definition" "taskdef" {
  family                = var.family
  container_definitions = var.container_definition
  task_role_arn         = aws_iam_role.task_role.arn
  execution_role_arn    = aws_iam_role.ecs_tasks_execution_role.arn
  network_mode          = var.network_mode
  tags                  = var.tags

  volume {
    name      = lookup(var.volume, "name", "dummy")
    host_path = lookup(var.volume, "host_path", "/tmp/dummy_volume")
  }
  dynamic "placement_constraints" {
    for_each = var.placement_constraint_on_demand_only == true ? [1] : []
    content {
      type       = "memberOf"
      expression = "attribute:lifecycle == on-demand"
    }
  }
}

resource "aws_iam_role_policy" "role_policy" {
  name_prefix = local.name_prefix
  role        = aws_iam_role.task_role.id
  policy      = var.policy
}

resource "aws_iam_role_policy" "ecs_exec_policy" {
  name = "ecs_exec_policy"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ecs:ExecuteCommand",
          "ecs:DescribeTasks",
          "firehose:Put*"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "task_role" {
  name_prefix = local.name_prefix
  description = "Task role for ${var.family}"

  assume_role_policy = var.assume_role_policy == "" ? data.aws_iam_policy_document.instance-assume-role-policy.json : var.assume_role_policy
}

data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_tasks_execution_role" {
  name_prefix        = local.name_prefix
  description        = "Task execution role for ${var.family}"
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy.json
}



data "aws_caller_identity" "current" {
  count = var.is_test ? 0 : 1
}

data "aws_region" "current" {
}

data "aws_iam_policy_document" "execution-role-policy" {
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = ["arn:aws:s3:::firelens*"]
  }

  statement {
    actions = [
      "secretsmanager:List*",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${local.account_id}:secret:platform_secrets/*"]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${local.account_id}:secret:${local.team}/${var.env}/${local.component}/*"]
  }

  dynamic "statement" {
    for_each = var.custom_secrets
    content {
      actions = [
        "secretsmanager:GetSecretValue"
      ]
      resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${local.account_id}:secret:${statement.value}-*"]
    }
  }
}

resource "aws_iam_role_policy" "execution_role_policy" {
  role   = aws_iam_role.ecs_tasks_execution_role.id
  name   = "role_policy"
  policy = data.aws_iam_policy_document.execution-role-policy.json
}
