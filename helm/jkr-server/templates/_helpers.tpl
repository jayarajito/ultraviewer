{{/*
Chart name, overridable with --set nameOverride.
*/}}
{{- define "jkr-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name (kept short; 63-char limit). Overridable with fullnameOverride.
*/}}
{{- define "jkr-server.fullname" -}}
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

{{/*
Chart label value "<name>-<version>".
*/}}
{{- define "jkr-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels. Stable across upgrades; never add volatile values here.
*/}}
{{- define "jkr-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "jkr-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Common labels applied to every resource.
*/}}
{{- define "jkr-server.labels" -}}
helm.sh/chart: {{ include "jkr-server.chart" . }}
{{ include "jkr-server.selectorLabels" . }}
app.kubernetes.io/part-of: justkeepremote
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
ServiceAccount name to use.
*/}}
{{- define "jkr-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "jkr-server.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Image reference. Fails the render early (instead of producing a broken Deployment)
when the repository or tag was not supplied.
*/}}
{{- define "jkr-server.image" -}}
{{- if not .Values.image.repository -}}
{{- fail "image.repository is required (the deploy workflow passes --set image.repository=<ECR URI>)" -}}
{{- end -}}
{{- if not .Values.image.tag -}}
{{- fail "image.tag is required (the deploy workflow passes --set image.tag=<git-sha>)" -}}
{{- end -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}

{{/*
Relay host handed to clients. Required: with a wrong/empty value every client would be
told to relay through an address that does not exist. Values are also constrained by
values.schema.json; this gives a clearer message and rejects the empty default.
*/}}
{{- define "jkr-server.relayHost" -}}
{{- required "relayHost is required: the public DNS name or IP clients use to reach this server (deploy workflow: GitHub Environment variable RELAY_HOST)" .Values.relayHost -}}
{{- end -}}

{{/*
The full set of ports the two processes bind, derived from the two configured base
ports exactly the way rustdesk-server does it (verified in src/rendezvous_server.rs and
src/relay_server.rs):
    hbbs --port P  ->  P (tcp+udp, signalling)   P-1 (tcp, NAT test)   P+2 (tcp, websocket)
    hbbr --port R  ->  R (tcp, relay)            R+2 (tcp, websocket)
Rendered as JSON; callers pipe the include of this template through fromJson.
FAILS the render if any two of those five ports coincide.
*/}}
{{- define "jkr-server.ports" -}}
{{- $r := int64 .Values.ports.rendezvous -}}
{{- $rl := int64 .Values.ports.relay -}}
{{- $m := dict "rendezvous" $r "natTest" (sub $r 1) "hbbsWebsocket" (add $r 2) "relay" $rl "hbbrWebsocket" (add $rl 2) -}}
{{- $seen := dict -}}
{{- range $name, $port := $m -}}
{{- $key := toString $port -}}
{{- if hasKey $seen $key -}}
{{- fail (printf "port collision: %s and %s both resolve to %s (ports.rendezvous=%d, ports.relay=%d)" $name (get $seen $key) $key $r $rl) -}}
{{- end -}}
{{- $_ := set $seen $key $name -}}
{{- end -}}
{{- toJson $m -}}
{{- end -}}
