{{/*
llm-stack helpers
*/}}

{{- define "llm-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "llm-stack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "llm-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "llm-stack.labels" -}}
helm.sh/chart: {{ include "llm-stack.chart" . }}
{{ include "llm-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "llm-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "llm-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Component-specific label helpers. `component` is a short string
(e.g. "inference", "vector-db", "gateway", "otel-collector").
*/}}
{{- define "llm-stack.componentLabels" -}}
{{ include "llm-stack.labels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "llm-stack.componentSelectorLabels" -}}
{{ include "llm-stack.selectorLabels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Render an image reference given a map with `repository` and `tag` keys,
honoring .Values.global.imageRegistry when set.
Usage:
  {{ include "llm-stack.image" (dict "image" .Values.inference.image "global" .Values.global) }}
*/}}
{{- define "llm-stack.image" -}}
{{- $registry := .global.imageRegistry | default "" -}}
{{- $repository := .image.repository -}}
{{- $tag := .image.tag | default "latest" -}}
{{- if $registry -}}
{{ printf "%s/%s:%s" $registry $repository $tag }}
{{- else -}}
{{ printf "%s:%s" $repository $tag }}
{{- end -}}
{{- end -}}

{{- define "llm-stack.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range . }}
  - name: {{ .name }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "llm-stack.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "llm-stack.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
