{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
When apps are created in the org namespace add a cluster prefix.
*/}}
{{- define "app.name" -}}
{{/*
for capi MCs and WCs this will be clusterId-appName
*/}}
{{- if hasPrefix "org-" .ns -}}
{{- printf "%s-%s" .cluster .app -}}
{{- else -}}
{{/*
for vintage MCs and WCs this will just be .app
*/}}
{{- .app -}}
{{- end -}}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "labels.selector" -}}
app.kubernetes.io/name: {{ include "name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "labels.common" -}}
{{ include "labels.selector" . }}
app.giantswarm.io/branch: {{ .Chart.Annotations.branch | replace "#" "-" | replace "/" "-" | replace "." "-" | trunc 63 | trimSuffix "-" | quote }}
application.giantswarm.io/commit: {{ .Chart.Annotations.commit | quote }}
application.giantswarm.io/team: {{ index .Chart.Annotations "application.giantswarm.io/team" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
giantswarm.io/cluster: {{ .Values.clusterID | quote }}
giantswarm.io/managed-by: {{ .Release.Name | quote }}
giantswarm.io/service-type: {{ .Values.serviceType }}
helm.sh/chart: {{ include "chart" . | quote }}
{{- end -}}

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
