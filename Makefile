SHELL := /bin/bash
AWS_REGION := ${AWS_REGION}
AWS_DIR=$(CURDIR)/terraform/amazon
TERRAFORM_BUCKET := ${TERRAFORM_BUCKET}
ENV := ${ENV}
GLUE_SCRIPT_BUCKET := ${GLUE_SCRIPT_BUCKET}
GLUE_SCRIPT_LOCAL_PATH := ${GLUE_SCRIPT_LOCAL_PATH}
GLUE_JOB_NAME := ${GLUE_JOB_NAME}
GLUE_JOB_ROLE_ARN := ${GLUE_JOB_ROLE_ARN}
TERRAFORM_FLAGS :=
AWS_TERRAFORM_FLAGS = -var "region=$(AWS_REGION)" \
		-var "env=$(ENV)" \
		-var "script_key=$()" \
		-var "bucket=$(TERRAFORM_BUCKET)" \
		-var "glue_script_bucket=$(GLUE_SCRIPT_BUCKET)" \
		-var "glue_job_name=$(GLUE_JOB_NAME)" \
		-var "glue_job_role_arn=$(GLUE_JOB_ROLE_ARN)" \
		-var "glue_script_local_path=$(GLUE_SCRIPT_PATH)"

.PHONY: aws-init
aws-init:
	@:$(call check_defined, AWS_REGION, Amazon Region)
	@:$(call check_defined, ENV, Environment (staging or production))
	@:$(call check_defined, TERRAFORM_BUCKET, s3 bucket name to store the terraform state)
	@:$(call check_defined, GLUE_SCRIPT_BUCKET, s3 bucket name to store the Glue job script)
	@:$(call check_defined, GLUE_SCRIPT_LOCAL_PATH, local path to Glue job script)
	@:$(call check_defined, GLUE_JOB_NAME, Glue job name)
	@:$(call check_defined, GLUE_JOB_ROLE_ARN, ARN of IAM role to run Glue job)
	@cd $(AWS_DIR) && terraform init \
		-backend-config "bucket=$(TERRAFORM_BUCKET)" \
		-backend-config "region=$(AWS_REGION)" \
		$(AWS_TERRAFORM_FLAGS)

.PHONY: terraform-validate
terraform-validate: ## Validate terraform scripts.
	@cd $(AWS_DIR) && echo "$$(docker run --rm -it --entrypoint bash -w '/mnt' -v $$(pwd):/mnt hashicorp/terraform -c 'terraform validate -check-variables=false . && echo [OK] terraform')"

.PHONY: aws-plan
aws-plan: aws-init ## Run terraform plan for Amazon.
	@cd $(AWS_DIR) && terraform plan \
		$(AWS_TERRAFORM_FLAGS)

.PHONY: aws-apply
aws-apply: aws-init ## Run terraform apply for Amazon.
	@cd $(AWS_DIR) && terraform apply \
		$(AWS_TERRAFORM_FLAGS) \
		$(TERRAFORM_FLAGS)

check_defined = \
				$(strip $(foreach 1,$1, \
				$(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
				  $(if $(value $1),, \
				  $(error Undefined $1$(if $2, ($2))$(if $(value @), \
				  required by target `$@')))

.PHONY: update
update: update-terraform ## Update terraform binary locally.

TERRAFORM_BINARY:=$(shell which terraform || echo "/usr/local/bin/terraform")
TMP_TERRAFORM_BINARY:=/tmp/terraform
.PHONY: update-terraform
update-terraform: ## Update terraform binary locally from the docker container.
	@echo "Updating terraform binary..."
	$(shell docker run --rm --entrypoint bash hashicorp/terraform -c "cd \$\$$(dirname \$\$$(which terraform)) && tar -Pc terraform" | tar -xvC $(dir $(TMP_TERRAFORM_BINARY)) > /dev/null)
	sudo mv $(TMP_TERRAFORM_BINARY) $(TERRAFORM_BINARY)
	sudo chmod +x $(TERRAFORM_BINARY)
	@echo "Update terraform binary: $(TERRAFORM_BINARY)"
	@terraform version

# if this session isn't interactive, then we don't want to allocate a
# TTY, which would fail, but if it is interactive, we do want to attach
# so that the user can send e.g. ^C through.
INTERACTIVE := $(shell [ -t 0 ] && echo 1 || echo 0)
ifeq ($(INTERACTIVE), 1)
	DOCKER_FLAGS += -t
endif

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
