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
Get trust policy statements for all provided OIDC domains
*/}}
{{- define "aws-nth-bundle.trustPolicyStatements" -}}
{{- $cmvalues := (include "aws-nth-bundle.crossplaneConfigData" .) | fromYaml -}}
{{- $saName := default (include "aws-nth-bundle.fullname" .) .Values.serviceAccount.name -}}
{{- range $index, $oidcDomain := $cmvalues.oidcDomains -}}
{{- if not (eq $index 0) }}, {{ end }}{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:{{ $cmvalues.awsPartition }}:iam::{{ $cmvalues.accountID }}:oidc-provider/{{ $oidcDomain }}"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringLike": {
      "{{ $oidcDomain }}:sub": "system:serviceaccount:kube-system:{{ $saName }}"
    }
  }
}
{{- end -}}
{{- end -}}

{{/*
Set Giant Swarm specific values — computes IRSA role ARN and SQS queue URL.
*/}}
{{- define "giantswarm.setValues" -}}
{{- $cmvalues := (include "aws-nth-bundle.crossplaneConfigData" .) | fromYaml -}}
{{- $clusterID := (include "aws-nth-bundle.clusterID" .) -}}
{{- $_ := set .Values.serviceAccount.annotations "eks.amazonaws.com/role-arn" (printf "arn:%s:iam::%s:role/%s-nth" $cmvalues.awsPartition $cmvalues.accountID $clusterID) -}}
{{- if not .Values.queueURL -}}
{{- $_ := set .Values "queueURL" (printf "%s-nth" $clusterID) -}}
{{- end -}}
{{- if and (not .Values.clusterName) -}}
{{- $_ := set .Values "clusterName" $clusterID -}}
{{- end -}}
{{- end -}}

{{/*
Reusable: combine GS split registry+name into upstream single repository.
Note: GS uses image.name (not image.repository), so we combine registry+name.
*/}}
{{- define "giantswarm.combineImage" -}}
{{- $result := deepCopy . -}}
{{- if .name -}}
{{- $_ := set $result "repository" (printf "%s/%s" .registry .name) -}}
{{- $_ := unset $result "registry" -}}
{{- $_ := unset $result "name" -}}
{{- else -}}
{{- $_ := set $result "repository" (printf "%s/%s" .registry .repository) -}}
{{- $_ := unset $result "registry" -}}
{{- end -}}
{{- $result | toYaml -}}
{{- end -}}

{{/*
Transform flat bundle values into the nested workload chart structure.
*/}}
{{- define "giantswarm.workloadValues" -}}
{{- include "giantswarm.setValues" . -}}
{{- $upstreamValues := dict -}}

{{/* Keys that belong to the bundle chart itself (never forwarded) */}}
{{- $bundleOnlyKeys := list "ociRepositoryUrl" "clusterID" "clusterName" -}}
{{/* Keys forwarded as workload extras (not under upstream:) */}}
{{- $extrasKeys := list "networkPolicy" "verticalPodAutoscaler" "global" -}}
{{/* Keys with special handling */}}
{{- $specialKeys := list "image" -}}
{{- $reservedKeys := concat $bundleOnlyKeys $extrasKeys $specialKeys -}}

{{/* Image: combine GS split format */}}
{{- $_ := set $upstreamValues "image" (include "giantswarm.combineImage" .Values.image | fromYaml) -}}

{{/* Preserve the original chart name for selector compatibility */}}
{{- $_ := set $upstreamValues "nameOverride" "aws-node-termination-handler" -}}

{{/* Pass through any non-reserved value to upstream */}}
{{- range $key, $val := .Values -}}
  {{- if not (has $key $reservedKeys) -}}
  {{- $_ := set $upstreamValues $key $val -}}
  {{- end -}}
{{- end -}}

{{/* Assemble workload values: upstream + extras */}}
{{- $workloadValues := dict "upstream" $upstreamValues -}}
{{- $_ := set $workloadValues "networkPolicy" .Values.networkPolicy -}}
{{- $_ := set $workloadValues "verticalPodAutoscaler" .Values.verticalPodAutoscaler -}}
{{- $_ := set $workloadValues "global" .Values.global -}}

{{- $workloadValues | toYaml -}}
{{- end -}}
