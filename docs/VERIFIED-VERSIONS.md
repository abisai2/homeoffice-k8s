# Verified Upstream Versions & Config Notes

> **Rule:** do NOT trust training data for the software stack. Before authoring a
> component's config, fetch its **current** upstream version/schema (live registry, `helm
> show values`, `talosctl images`, GitHub API) and record it here: pinned version, source,
> date, and config-schema notes (esp. keys that changed). Renovate keeps these current.
>
> Status: ⛔ PENDING · ✅ VERIFIED. Filled at each component's `.0` checkpoint.

| Component | Pinned version | Source of truth (verified via) | Verified | Notes |
|---|---|---|---|---|
| Talos Linux | **v1.13.3** ✅ | GitHub releases API (latest v1.13.x) | 2026-06-03 | installed talosctl client matches |
| Kubernetes | **v1.36.1** ✅ | `talosctl images default` (kube-apiserver/kubelet) | 2026-06-03 | etcd v3.6.11; installed kubectl 1.36.1 matches |
| Talos machine config | v1.13.3 schema ✅ | `talosctl gen config` sample + `talosctl validate --mode metal` | 2026-06-03 | install.disk `/dev/sda`; `allowSchedulingOnControlPlanes` default false (CPs tainted); CNI none + proxy disabled at cluster level; **trailing `kind: HostnameConfig` doc quirk persists** → stripped in talos-gen.sh |
| Talos Image Factory | **schematic `a28d86375cf9debe952efbcbe8e2886cf0a174b1f4dd733512600a40334977d7`** ✅ | factory.talos.dev (POST /schematics) | 2026-06-03 | Source of truth: `talos/image/schematic.yaml`; regen via `scripts/talos-image.sh id`. Ext `iscsi-tools` + `util-linux-tools` (Longhorn) **+ `vmtoolsd-guest-agent`** (talos-vmtoolsd → vCenter guest IP/hostname/heartbeat/power). OVA `image/<id>/v1.13.3/vmware-amd64.ova` HTTP 200; installer `factory.talos.dev/installer/a28d8637…77d7:v1.13.3` (in `install.image`). _Correction: the prior `613e1592…` schematic had NO guest-agent ext; vCenter only showed open-vm-tools "guest-managed/2147483647/Not running" because that flag is **static OVA metadata** (present even on the never-booted template) — a running daemon requires this extension._ |
| Terraform | **v1.15.5** ✅ | installed | 2026-06-03 | supports S3 backend `use_lockfile` |
| vsphere provider | **vmware/vsphere 2.16.0** ✅ | registry.terraform.io/v1/providers/vmware/vsphere | 2026-06-03 | provider MOVED hashicorp→vmware (hashicorp mirror stale at 2.12); init+validate OK; verify `vsphere_virtual_machine`/anti-affinity schema at P1.3 |
| Gateway API CRDs | **v1.4.1** ✅ | Cilium v1.19 docs (servicemesh/gateway-api) | 2026-06-04 | standard channel; install before Cilium gatewayAPI. **Repin 2026-06-04: was v1.5.1 ("latest") — wrong.** Cilium 1.19.x is version-coupled and requires **v1.4.1** (gatewayclasses/gateways/httproutes/grpcroutes/referencegrants); v1.5.1 would make cilium-operator disable/error Gateway API. Bundle `…/releases/download/v1.4.1/standard-install.yaml` (HTTP 200, `bundle-version: v1.4.1`). **Also need the EXPERIMENTAL `tlsroutes` CRD** (`…/v1.4.1/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml`): cilium-operator 1.19 registers `v1alpha2.TLSRoute` in its scheme + watches it unconditionally, so without it (present at operator startup) it error-loops on every gateway reconcile — verified live 2026-06-04. **GatewayClass gotcha:** chart `gatewayAPI.gatewayClass.create` defaults to `auto` (emits the GatewayClass only if the live cluster already has the API), which an OFFLINE `kustomize build --enable-helm` (bootstrap + Argo) always evaluates false → set `create: "true"` in values. |
| Cilium (chart) | **1.19.4** ✅ | helm repo cilium + cilium v1.19.4 source | 2026-06-03 | kubeProxyReplacement:true, k8sServiceHost=VIP .30:6443, l2announcements+gatewayAPI on; **CiliumLoadBalancerIPPool → cilium.io/v2** (promoted), **CiliumL2AnnouncementPolicy → v2alpha1**; render 34 obj + kubeconform OK |
| Argo CD (chart) | **9.5.17** ✅ (app v3.4.3) | helm repo argo/argo-cd | 2026-06-03 | KSOPS repo-server wiring (initContainer + sops-age vol + SOPS_AGE_KEY_FILE); render 53 obj kubeconform OK; matches argocd CLI v3.4.3 |
| KSOPS | **v4.5.1** ✅ | github viaduct-ai/kustomize-sops | 2026-06-03 | image `viaductoss/ksops:v4.5.1` (note viaductoss); `kustomize.buildOptions: --enable-alpha-plugins --enable-exec --enable-helm` |
| SOPS | installed ✅ | mgmt | 2026-06-03 | round-trip verified P0.2 |
| cert-manager (chart) | ⛔ | https://cert-manager.io/docs | — | Cloudflare DNS-01 solver; recursive NS for split-horizon (P7.1) |
| Longhorn (chart) | ⛔ | https://longhorn.io/docs | — | **backup-target setting key**; node scheduling (P7.3) |
| CloudNativePG (operator) | ⛔ | https://cloudnative-pg.io/documentation/ | — | `Cluster`/`ScheduledBackup` API group+version (P7.4) |
| Authentik (chart) | ⛔ | https://docs.goauthentik.io | — | external CNPG DSN, Redis, media PVC (P7.6) |
| Velero (chart + plugin) | ⛔ | https://velero.io/docs · velero-plugin-for-aws | — | AWS plugin for Wasabi (custom endpoint/region) (P7.7) |
| Renovate | ⛔ | https://docs.renovatebot.com | — | manager config refined at P7 |
| govc | 0.52.0 ✅ | installed | 2026-06-03 | template import + discovery |
