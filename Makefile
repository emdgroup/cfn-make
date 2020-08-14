#!/usr/bin/make -f

.PHONY: check-dependencies init test build create stage update
SHELL=/bin/bash -o pipefail

CONFIGDIR = $(shell dirname $(CONFIG))

export AWS_PAGER =
export AWS_DEFAULT_OUTPUT = json

CLI = aws cloudformation

-include *.makefile

ARTIFACT = .build/$(CONFIG).json

STACKNAME = $(shell jq -r '.StackName' .build/$(CONFIG).json)

check-dependency = $(if $(shell command -v $(1)),,$(error Make sure $(1) is installed))

check-dependencies:
	@$(call check-dependency,aws)
	@$(call check-dependency,jq)
	@$(call check-dependency,shasum)
	@$(call check-dependency,cfn-include)
	@cfn-include --version | perl -pe 'use version; exit(version->parse("v$$_") < version->parse("v0.11.0"))' || \
		(echo "requires cfn-include 0.11.0 or higher" && exit 1)

run-hook = $(MAKE) -n -f $(CONFIGDIR)/Makefile $(1) > /dev/null 2>&1; if [ "$$?" -eq "2" ]; then true; else echo "running $(1) hook" && ARTIFACT=$(ARTIFACT) $(MAKE) -f $(CONFIGDIR)/Makefile $(1); fi

init: check-dependencies
	@$(call run-hook,pre-init)
ifndef CONFIG
	$(error CONFIG needs to be set to a file or directory)
endif
	@$(call run-hook,post-init)

test-inline = jq -r '.TemplateBody' $(ARTIFACT) > $(ARTIFACT).template && $(CLI) validate-template --template-body file://$(ARTIFACT).template > /dev/null

test-url = jq -r '.TemplateURL' $(ARTIFACT) | xargs $(CLI) validate-template --template-url > /dev/null

test: build
	@$(call run-hook,pre-test)
	@jq -e '.TemplateBody' $(ARTIFACT) > /dev/null; if [ "$$?" -eq "0" ]; then $(test-inline); else $(test-url); fi
	@$(call run-hook,post-test)

build: init clean
	@$(call run-hook,pre-build)
	@mkdir -p .build/$(CONFIG)
	@cfn-include $(CONFIG) > $(ARTIFACT)
	@$(call run-hook,post-build)

outputs =	$(CLI) describe-stacks --stack-name $(STACKNAME) --query 'Stacks[].Outputs[]' --output table

create: test
	@$(call run-hook,pre-create)
	@$(CLI) create-stack --cli-input-json file://$(ARTIFACT) --output text
	@$(CLI) wait stack-create-complete --stack-name $(STACKNAME)
	@$(call run-hook,post-create)
	@$(call run-hook,post-create-or-update)
	@$(call outputs)

CHANGESET = $(shell shasum $(ARTIFACT) | awk '{print "cfnmake-"$$1}')

download-template = @if jq -e '.TemplateURL' $(ARTIFACT) > /dev/null; then \
		URL=$$(jq -j '.TemplateURL' $(ARTIFACT) | perl -pe 's!^.*?.amazonaws.com/([^/]+)!s3://$$1!g'); \
		echo '{"Fn::Include":'$$URL'}' | cfn-include --yaml > .build/$(CONFIG).json.template; \
	fi

diff: test
	@$(call run-hook,pre-diff)
	@$(CLI) get-template --stack-name $(STACKNAME) --query TemplateBody | cfn-include --yaml > .build/$(CONFIG).template.cur
	@$(CLI) describe-stacks --stack-name $(STACKNAME) --query 'Stacks[0]' | jq '.Parameters // [] | sort_by(.ParameterKey)' | cfn-include --yaml > .build/$(CONFIG).params.cur
	@jq '.Parameters // [] | sort_by(.ParameterKey)' .build/$(CONFIG).json | cfn-include --yaml > .build/$(CONFIG).params.new
	@git --no-pager diff --no-index .build/$(CONFIG).params.cur .build/$(CONFIG).params.new || true
	$(call download-template)
	@test -f .build/$(CONFIG).json.template && cfn-include --yaml .build/$(CONFIG).json.template > .build/$(CONFIG).template.new || echo Cannot download TemplateUrl, skipping diff
	@test -f .build/$(CONFIG).json.template && git --no-pager diff --no-index .build/$(CONFIG).template.cur .build/$(CONFIG).template.new || true
	@$(call run-hook,post-diff)

stage: diff
	@$(call run-hook,pre-stage)
	@$(CLI) delete-change-set --stack-name $(STACKNAME) --change-set-name $(CHANGESET)
	@$(CLI) create-change-set --cli-input-json file://$(ARTIFACT) --change-set-name $(CHANGESET) --change-set-type UPDATE --output text --query 'Id'
	@$(CLI) wait change-set-create-complete --change-set-name $(CHANGESET) --stack-name $(STACKNAME)
	@$(CLI) describe-change-set --stack-name $(STACKNAME) --change-set-name $(CHANGESET) --output table --query "Changes[].{Action: ResourceChange.Action, LogicalId: ResourceChange.LogicalResourceId, Type: ResourceChange.ResourceType, Replacement: ResourceChange.Replacement, ResourceParameterStatic: join(', ', ResourceChange.Details[?Evaluation=='Static'].Target.Name), ResourceParameterDynamic: join(', ', ResourceChange.Details[?Evaluation=='Dynamic'].Target.Name)}"
	@$(call run-hook,post-stage)

update: init
	@$(call run-hook,pre-update)
	@$(CLI) execute-change-set --stack-name $(STACKNAME) --change-set-name $(CHANGESET)
	@$(CLI) wait stack-update-complete --stack-name  $(STACKNAME)
	@$(call run-hook,post-update)
	@$(call run-hook,post-create-or-update)
	@$(call outputs)

clean:
	@$(call run-hook,pre-clean)
	@rm -rf .build/$(CONFIG)
	@$(call run-hook,post-clean)
