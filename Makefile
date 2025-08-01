## Copyright 2024 Red Hat, Inc.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

default: image

HUB ?= quay.io/sail-dev
TAG ?= 3.0

lint:
	find . -name '*.sh' -print0 | xargs -0 -r shellcheck

image:
	podman build -t ${HUB}/istio-must-gather:${TAG} .

push: image
	podman push ${HUB}/istio-must-gather:${TAG}

