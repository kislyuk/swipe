locals {
  app_slug = "${var.app_name}-${var.deployment_environment}"
  sfn_template_file = var.sfn_template_file == "" ? "${path.module}/sfn-templates/single-wdl-1.json" : var.sfn_template_file
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "swipe_sfn_service" {
  name = "${local.app_slug}-sfn-service"
  policy = templatefile("${path.module}/../../iam_policy_templates/sfn_service.json", {
    APP_NAME               = var.app_name,
    DEPLOYMENT_ENVIRONMENT = var.deployment_environment,
    sfn_service_role_name  = "${local.app_slug}-sfn-service",
    AWS_DEFAULT_REGION     = data.aws_region.current.name,
    AWS_ACCOUNT_ID         = data.aws_caller_identity.current.account_id,
  })
}

resource "aws_iam_role" "swipe_sfn_service" {
  name = "${local.app_slug}-sfn-service"
  assume_role_policy = templatefile("${path.module}/../../iam_policy_templates/trust_policy.json", {
    trust_services = ["states"]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "swipe_sfn_service" {
  role       = aws_iam_role.swipe_sfn_service.name
  policy_arn = aws_iam_policy.swipe_sfn_service.arn
}

module "batch_job" {
  source                      = "../swipe-sfn-batch-job"
  app_name                    = var.app_name
  batch_job_docker_image_name = var.batch_job_docker_image_name
  batch_job_timeout_seconds   = var.batch_job_timeout_seconds
  deployment_environment      = var.deployment_environment
  tags                        = var.tags
}

module "sfn-io-helper" {
  source = "../swipe-sfn-io-helper-lambda"
}

locals {
  sfn_common_params = {
    deployment_environment    = var.deployment_environment,
    batch_spot_job_queue_name = var.batch_spot_job_queue_name,
    batch_ec2_job_queue_name  = var.batch_ec2_job_queue_name,
    batch_job_definition_name = module.batch_job.batch_job_definition_name,
  }
  sfn_tags = merge(var.tags, {
  })
}

resource "aws_sfn_state_machine" "swipe_single_wdl_1" {
  name     = "${local.app_slug}-single-wdl-1"
  role_arn = aws_iam_role.swipe_sfn_service.arn
  definition = templatefile(local.sfn_template_file, merge(local.sfn_common_params, {
    batch_job_name_prefix = "${local.app_slug}-single-wdl",
  }))
  tags = local.sfn_tags
}
