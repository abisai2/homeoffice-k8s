# ADR-0004: Cilium for CNI, L2 LoadBalancer, and Gateway API

- **Status:** Accepted
- **Date:** 2026-06-04

## Context

The cluster needs three networking capabilities that are often three separate projects: a CNI,
a way to expose `LoadBalancer` Services on a bare-metal/VMware network with no cloud LB, and an
ingress layer. The classic stack is `<some CNI>` + MetalLB + an Ingress controller (e.g.
ingress-nginx). Talos ships with **no CNI and no kube-proxy** by design (`cni: none`,
`proxy.disabled: true` in `talos/patches/controlplane.yaml`), so something must provide all of
this — and on first boot the nodes sit `NotReady` until it does.

Cilium can provide the whole set in one component: eBPF CNI, a full kube-proxy replacement, L2
Announcements + LB-IPAM for `LoadBalancer` Services, and a Gateway API implementation. Gateway
API (the successor to Ingress) was chosen over an Ingress controller because it is the direction
the ecosystem is moving and it models TLS, listeners, and routes more cleanly. The cost is
coupling: collapsing four concerns into one means Cilium's correctness and version constraints
become load-bearing for everything.

## Decision

Use **Cilium 1.19.4** as the single networking layer (`kubernetes/apps/cilium/`):

- `kubeProxyReplacement: true`, reaching the API via the control-plane VIP
  (`k8sServiceHost: 172.16.23.30`) since there is no kube-proxy to do it.
- **L2 Announcements + LB-IPAM** for `LoadBalancer` Services — a `CiliumLoadBalancerIPPool`
  (`cilium.io/v2`) carving out `172.16.23.120–.139` and a `CiliumL2AnnouncementPolicy`
  (`cilium.io/v2alpha1`). No MetalLB.
- **Gateway API** (`gatewayAPI.enabled: true`) providing the `cilium` GatewayClass; a single
  shared `Gateway main` lands on `.120` and apps attach via `HTTPRoute`.

Cilium is installed first (sync-wave `-10`) at bootstrap so the nodes go `Ready`.

## Consequences

- **Easier:** one chart, one set of CRDs, one thing to upgrade for CNI + LB + ingress. eBPF
  kube-proxy replacement; Hubble for flow visibility; a single VIP pool and one Gateway shared
  by all apps.
- **Harder / costs accepted:** tight version coupling, learned the hard way. Cilium 1.19 is
  pinned to **Gateway API v1.4.1** (not "latest" v1.5.1, which makes the operator disable
  Gateway API), and it needs the **experimental `tlsroutes` CRD** present at operator start or
  it error-loops every reconcile. Offline `kustomize --enable-helm` renders also forced
  `gatewayClass.create: "true"` because the chart's `auto` default checks live-cluster
  capabilities that an offline render can't see. These gotchas are recorded in
  `VERIFIED-VERSIONS.md`. L2 mode means the LB IPs are layer-2 only (single broadcast domain,
  one node answers per IP) — fine for this VLAN, not a routed/ECMP design.
