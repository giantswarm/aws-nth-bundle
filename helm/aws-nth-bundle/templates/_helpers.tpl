{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "aws-nth-bundle.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "aws-nth-bundle.fullname" -}}
{{- $name := .Chart.Name -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "aws-nth-bundle.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Resolve clusterID: use .Values.clusterID if set, otherwise derive from
the release name by stripping known chart name suffixes.
*/}}
{{- define "aws-nth-bundle.clusterID" -}}
{{- if .Values.clusterID -}}
  {{- .Values.clusterID -}}
{{- else -}}
  {{- $name := .Release.Name -}}
  {{- range $suffix := list (printf "-%s" $.Chart.Name) "-aws-nth-bundle" "-aws-node-termination-handler-bundle" -}}
    {{- $name = trimSuffix $suffix $name -}}
  {{- end -}}
  {{- if eq $name .Release.Name -}}
    {{- fail "clusterID not set and cannot derive cluster name from release name" -}}
  {{- end -}}
  {{- $name -}}
{{- end -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "aws-nth-bundle.labels" -}}
app.kubernetes.io/name: {{ include "aws-nth-bundle.name" . }}
helm.sh/chart: {{ include "aws-nth-bundle.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
giantswarm.io/service-type: "managed"
application.giantswarm.io/team: {{ index .Chart.Annotations "application.giantswarm.io/team" | quote }}
giantswarm.io/cluster: {{ include "aws-nth-bundle.clusterID" . | quote }}
cluster.x-k8s.io/cluster-name: {{ include "aws-nth-bundle.clusterID" . | quote }}
{{- end -}}

{{/*
Fetch crossplane config ConfigMap data
*/}}
{{- define "aws-nth-bundle.crossplaneConfigData" -}}
{{- $clusterName := (include "aws-nth-bundle.clusterID" .) -}}
{{- $configmap := (lookup "v1" "ConfigMap" .Release.Namespace (printf "%s-crossplane-config" $clusterName)) -}}
{{- $cmvalues := dict -}}
{{- if and $configmap $configmap.data $configmap.data.values -}}
  {{- $cmvalues = fromYaml $configmap.data.values -}}
{{- else -}}
  {{- fail (printf "Crossplane config ConfigMap %s-crossplane-config not found in namespace %s or has no data" $clusterName .Release.Namespace) -}}
{{- end -}}
{{- $cmvalues | toYaml -}}
{{- end -}}

{{/*
Get accountID from ConfigMap lookup
*/}}
{{- define "karpenter-bundle.accountID" -}}
{{- $cmvalues := (include "karpenter-bundle.crossplaneConfigData" .) | fromYaml -}}
{{- index $cmvalues "accountID" | default "" -}}
{{- end -}}

{{/*
Get awsPartition from ConfigMap lookup
*/}}
{{- define "karpenter-bundle.awsPartition" -}}
{{- $cmvalues := (include "karpenter-bundle.crossplaneConfigData" .) | fromYaml -}}
{{- index $cmvalues "awsPartition" | default "aws" -}}
{{- end -}}

{{/*
Get awsRegion from ConfigMap lookup
*/}}
{{- define "karpenter-bundle.awsRegion" -}}
{{- $cmvalues := (include "karpenter-bundle.crossplaneConfigData" .) | fromYaml -}}
{{- index $cmvalues "awsRegion" | default "eu-west-1" -}}
{{- end -}}

{{/*
Get trust policy statements for all provided OIDC domains
*/}}
{{- define "aws-nth-bundle.trustPolicyStatements" -}}
{{- $cmvalues := (include "aws-nth-bundle.crossplaneConfigData" .) | fromYaml -}}
{{- range $index, $oidcDomain := $cmvalues.oidcDomains -}}
{{- if not (eq $index 0) }}, {{ end }}{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:{{ $cmvalues.awsPartition }}:iam::{{ $cmvalues.accountID }}:oidc-provider/{{ $oidcDomain }}"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "{{ $oidcDomain }}:sub": "system:serviceaccount:kube-system:{{ $.Values.controller.serviceAccount.name }}"
    }
  }
}
{{- end -}}
{{- end -}}

{{/*
Full SQS queue URL for NTH
*/}}
{{- define "aws-nth-bundle.queueURL" -}}
{{- $accountID := include "aws-nth-bundle.accountID" . -}}
{{- $awsRegion := include "aws-nth-bundle.awsRegion" . -}}
{{- $clusterName := include "aws-nth-bundle.clusterID" . -}}
{{- printf "https://sqs.%s.amazonaws.com/%s/%s-nth" $awsRegion $accountID $clusterName -}}
{{- end -}}

{{/*
SQS Queue ARN
*/}}
{{- define "aws-nth-bundle.sqsQueueArn" -}}
{{- $accountID := include "aws-nth-bundle.accountID" . -}}
{{- $awsPartition := include "aws-nth-bundle.awsPartition" . -}}
{{- $awsRegion := include "aws-nth-bundle.awsRegion" . -}}
{{- $clusterName := include "aws-nth-bundle.clusterID" . -}}
{{- printf "arn:%s:sqs:%s:%s:%s-nth" $awsPartition $awsRegion $accountID $clusterName -}}
{{- end -}}

{{/*
Proxy values for aws-node-termination-handler
*/}}
{{- define "aws-nth-bundle.proxyValues" -}}
extraEnv:
{{- if .Values.proxy.http }}
- name: HTTP_PROXY
  value: {{ .Values.proxy.http | quote }}
{{- end }}
{{- if .Values.proxy.https }}
- name: HTTPS_PROXY
  value: {{ .Values.proxy.https | quote }}
{{- end }}
{{- if .Values.proxy.noProxy }}
- name: NO_PROXY
  value: {{ .Values.proxy.noProxy | quote }}
{{- end }}
{{ end -}}
