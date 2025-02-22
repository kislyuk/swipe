SHELL=/bin/bash -o pipefail

ifndef DEPLOYMENT_ENVIRONMENT
$(error Please run "source environment" in the repo root directory before running make commands)
endif

templates:
	for sfn_tpl in terraform/modules/swipe-sfn/sfn-templates/*.yml; do yq . $$sfn_tpl > $${sfn_tpl/.yml/.json}; done
	cd terraform/modules/swipe-sfn-batch-job; yq . batch_job_container_properties.yml > batch_job_container_properties.json

init-tf:
	-rm -f $(TF_DATA_DIR)/*.tfstate
	mkdir -p $(TF_DATA_DIR)
	jq -n ".region=\"us-west-2\" | .bucket=env.TF_S3_BUCKET | .key=env.APP_NAME+env.DEPLOYMENT_ENVIRONMENT" > $(TF_DATA_DIR)/aws_config.json
	terraform init

deploy: sfn-io-helper-lambda templates init-tf
	@if [[ $(DEPLOYMENT_ENVIRONMENT) == staging && $$(git symbolic-ref --short HEAD) != staging ]]; then echo Please deploy staging from the staging branch; exit 1; fi
	@if [[ $(DEPLOYMENT_ENVIRONMENT) == prod && $$(git symbolic-ref --short HEAD) != prod ]]; then echo Please deploy prod from the prod branch; exit 1; fi
	TF_VAR_APP_NAME=$(APP_NAME) TF_VAR_DEPLOYMENT_ENVIRONMENT=$(DEPLOYMENT_ENVIRONMENT) TF_VAR_OWNER=$(OWNER) TF_VAR_BATCH_SSH_PUBLIC_KEY='$(BATCH_SSH_PUBLIC_KEY)' terraform apply

deploy-mock: sfn-io-helper-lambda templates
	cp test/mock.tf .; unset TF_CLI_ARGS_init; terraform init; terraform apply --auto-approve

$(TFSTATE_FILE):
	terraform state pull > $(TFSTATE_FILE)

sfn-io-helper-lambda:
	jq .environment_variables.DEPLOYMENT_ENVIRONMENT=env.DEPLOYMENT_ENVIRONMENT $@/.chalice/config.json | sponge $@/.chalice/config.json
	envsubst < terraform/iam_policy_templates/$@.json > $@/.chalice/policy-$(DEPLOYMENT_ENVIRONMENT).json
	cd $@; export PYTHONPATH=vendor; chalice package --pkg-format terraform --stage $(DEPLOYMENT_ENVIRONMENT) ../terraform/modules/swipe-$@
	$(eval TF_JSON=terraform/modules/swipe-$@/chalice.tf.json)
	jq 'del(.environment_variables.DEPLOYMENT_ENVIRONMENT)' $@/.chalice/config.json | sponge $@/.chalice/config.json
	jq 'del(.provider.aws) | del(.terraform.required_version)' $(TF_JSON) | sponge $(TF_JSON)

lint: templates
	flake8 .
	statelint terraform/modules/*/sfn-templates/*.json
	mypy --check-untyped-defs --no-strict-optional .

get-logs:
	aegea logs --start-time=-5m --no-export /aws/lambda/$(APP_NAME)-$(DEPLOYMENT_ENVIRONMENT)

.PHONY: deploy templates init-tf sfn-io-helper-lambda lint
