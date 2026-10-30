# AGENTS.md

Guidance for coding agents working in this repository.

## What this repo is (ArgoCD GitOps, not an application)

`gitops` is the **ArgoCD declarative cluster-state repository** for the Flexible Interactive
Automation (FIA) service — it is **not** a software application. There is no application source
code, test runner, or package manifest here. Instead, **`main` IS the live desired state of the
`management`, `staging`, and `prod` Kubernetes clusters**:

- An ArgoCD **App of Apps** (`apps/app_of_apps/deployment.yml`, the only manifest applied manually
  to the `management` cluster) recursively watches `apps/` on `HEAD` of `main`.
- Every ArgoCD `Application` under `apps/` is configured with
  `syncPolicy.automated: {prune: true, selfHeal: true}`:
  - **`prune: true`**: Removing a resource from a Kustomization or deleting an Application manifest
    on `main` **immediately deletes that live resource from the target cluster**.
  - **`selfHeal: true`**: Manual `kubectl edit`/`kubectl apply` changes to ArgoCD-managed resources
    on the cluster are **immediately overwritten by ArgoCD** back to what is committed in this repo.

Read `README.md` for the zero-to-cluster bootstrap sequence, ArgoCD cluster registration, Vault
secret setup, local cluster manifests, and manual WSL staging deployment steps.

## Position in the FIA service

### Overarching FIA architecture

FIA is a multi-repository system (all checked out as siblings under the same parent workspace
directory) that automatically reduces instrument data, and also lets users browse, plot, and rerun
that data interactively:

```text
[ISIS Instrument Archive (/archive, /imat) & lastrun.txt]
        │
        ▼
  file-watcher (Kopf Operator + Per-Instrument Watcher Pods)
        │  publishes file path to RabbitMQ: `watched-files`
        ▼
  run-detection ◄──── fetches instrument rules (`GET /instrument/{inst}/specification`) ────► FIA-API
        │  ingests .nxs metadata, verifies rules, publishes JobRequest JSON
        │  to RabbitMQ: `scheduled-jobs` (or retries via `failed-watched-files`)
        ▼
  jobcontroller (job_creator) ◄──── requests PreScript (`GET /script/{inst}`) & posts Job ──► FIA-API ◄──► autoreduction-scripts
        │  spawns Kubernetes Job in cluster:
        ├──► Main container: runners (`ghcr.io/fiaisis/mantid` or `mantid-imaging`) -> writes reduced data to `/ceph`
        └──► Sidecar container: jobcontroller (job_watcher) -> updates job status/outputs in FIA-API (`PATCH /job/{id}`)

[Interactive / Web & Live Data Paths]
  scigateway (Host App) ──► frontend (FIA React Plugin)
                                ├──► fia-auth (UOWS login, JWT verify/refresh, `/experiments` RB lookup)
                                ├──► FIA-API (runs, jobs, scripts, specifications, reruns -> `watched-files` / `scheduled-jobs`)
                                └──► plotting-service (h5grove NeXus/HDF5 & IMAT image serving from `/ceph` & `/imat`)

  Kafka (`<INST>_events`, `<INST>_sampleEnv`, `<INST>_runInfo`)
        └──► live-data (Live Data Operator + Mantid Live Data Processor fetching `/live-data/{inst}/script` from FIA-API)

  LLSP (Long Lived Script Processors: `LLSP-API` + RabbitMQ + Celery `LLSP-Worker` built on `ghcr.io/fiaisis/mantid`)

[Infrastructure & Deployment]
  k8s (Terraform + Ansible for OpenStack clusters, Redpanda, local Minikube)
  gitops (THIS REPO) (ArgoCD App-of-Apps & Kustomize `base`/`envs`/`variants` manifests for all FIA services)
```

### This repository's location (upstream, downstream & siblings)

- **Role**: Single source of truth for everything deployed onto the FIA Kubernetes clusters (custom
  FIA microservices, operators/CRDs, RabbitMQ, Valkey, Envoy Gateway, Ceph/Archive/Manila/SMB
  storage mounts, HashiCorp Vault secret sync, GPU Operator, Falco, Cert-Manager, and monitoring).
- **Upstream writers (what pushes commits to `gitops`)**:
  - **Sibling FIA service CI pipelines**: On every push to `main` in a service repo, its GitHub
    Actions workflow builds a new GHCR container image, clones `fiaisis/gitops`, uses `yq` to write
    the new `@sha256:...` digest (or `*_SHA` env var) into
    `components/<service>/envs/staging/<service>.yml`, and pushes a `[CD] Update ...` commit directly
    to `main`:
    - `../FIA-API` -> `components/fia-api/envs/staging/fia-api.yml`
    - `../fia-auth` -> `components/fia-auth/envs/staging/fia-auth.yml`
    - `../plotting-service` -> `components/plotting-service/envs/staging/plotting-service.yml`
    - `../run-detection` -> `components/rundetection/envs/staging/rundetection.yml`
    - `../file-watcher` -> `components/file-watcher-operator/envs/staging/file-watcher-operator.yml`
      (updates both the operator image digest and `FILE_WATCHER_SHA256`)
    - `../jobcontroller` -> `components/jobcreator/envs/staging/jobcreator.yml` (updates both the
      `jobcreator` image digest and `WATCHER_SHA`)
    - `../runners` -> `components/jobcreator/envs/staging/jobcreator.yml` (updates
      `DEFAULT_RUNNER_SHA`)
    - `../live-data` -> `components/live-data-operator/envs/staging/live-data-operator.yml` (updates
      both the operator image digest and `LIVE_DATA_PROCESSOR_IMAGE_SHA`)
    - `../LLSP` -> `components/llsp-api/envs/staging/llsp-api.yml` and
      `components/llsp-worker/envs/staging/llsp-worker.yml`
    - `../frontend` -> `components/frontend/envs/staging/frontend.yml` (and
      `components/scigateway/envs/staging/scigateway.yml` when `container/*` SciGateway files change)
  - **`.github/workflows/prod_release.yml` (in this repo)**: On every push to `main`, copies
    `components/<service>/envs/staging/<service>.yml` to
    `components/<service>/envs/production/<service>.yml` across the FIA microservices and opens/updates
    the `staging_to_prod` pull request (`"[Automatic] Update prod from staging"`).
- **Downstream consumers**:
  - **ArgoCD on the `management` cluster** (provisioned via `../k8s`) continuously reconciles
    `apps/`, `projects/`, and `components/` against the `management`, `staging`, and `prod`
    clusters.

---

## Repository structure

```
apps/                        ArgoCD Application manifests (one subdirectory per application).
                              `apps/app_of_apps/deployment.yml` recursively syncs this entire
                              directory; each `<app>/deployment.yml` defines the staging, prod, and/or
                              management ArgoCD Application(s) pointing at `components/` or upstream
                              Helm charts
projects/                    ArgoCD AppProject definitions (`staging.yml`, `prod.yml`) scoping
                              allowed source repos, destination clusters, and namespaces
components/                  Kustomize manifests and raw Kubernetes resources for every workload and
                              cluster add-on (FIA microservices, RabbitMQ, Ceph/Archive/Manila/SMB
                              mounts, Envoy Gateway, Vault config, Falco, monitoring, node taints)
images/                      Utility container definitions (e.g. `openstack-cli/Dockerfile`)
.github/workflows/           `lint.yml` (`kube-linter` SARIF scan) and `prod_release.yml` (automated
                              `staging_to_prod` promotion PR)
.kube-linter.yml             Configuration for `kube-linter` (all built-in checks enabled)
```

---

## Kustomize 3-layer model: `base/` vs. `envs/` vs. `variants/` (Read This First)

Most FIA microservice components under `components/<service>/` use three directories:

```text
components/<service>/
  base/                      Shared resources (Deployment, Service, PVs/PVCs, VaultStaticSecret,
                              HTTPRoute, RBAC) common to all environments
  envs/
    staging/                 ArgoCD target path for the staging Application
    production/              ArgoCD target path for the prod Application (note: most components use
                              `envs/production/`, while `components/envoy/` uses `envs/prod/`)
  variants/
    staging/                 Kustomize `kind: Component` containing patches that must NEVER be
                              promoted to production (e.g. `DEV_MODE: "true"`, staging replica counts)
    production/              Kustomize `kind: Component` containing production-only patches
```

### The golden rule of `envs/` vs. `variants/`
Look at `.github/workflows/prod_release.yml`: on every push to `main`, it runs:
```shell
cp -rf ./components/$Service/envs/staging/$Service.yml ./components/$Service/envs/production/$Service.yml
```
for `fia-api`, `file-watcher-operator`, `frontend`, `jobcreator`, `plotting-service`, `rundetection`,
`scigateway`, `fia-auth`, and `live-data-operator`.

Because `prod_release.yml` **blindly overwrites `envs/production/<service>.yml` with
`envs/staging/<service>.yml`**:
1. **`envs/<env>/<service>.yml` is for promote-able state** — primarily the container `image:` digest
   and promoted image SHA env vars (`DEFAULT_RUNNER_SHA`, `WATCHER_SHA`, `FILE_WATCHER_SHA256`,
   `LIVE_DATA_PROCESSOR_IMAGE_SHA`) that flow from `staging` -> `production`.
2. **Any setting that must stay different between `staging` and `production`** (such as `DEV_MODE`,
   cluster-specific hostnames, or environment-specific resource limits/env vars) **MUST be placed in
   `variants/staging/` and `variants/production/`** (or in separate non-copied files in `envs/<env>/`,
   such as `*-secret.yml` or `httproute.yml`), **never** inside `envs/staging/<service>.yml` or
   `envs/production/<service>.yml`.

*(Note: `README.md`'s example tree shows `envs/prod/` and `variants/prod/`; in the actual repo on
`main`, most components use `envs/production/` and `variants/production/`.)*

---

## Secrets management (`VaultStaticSecret`) — strict agent rules

Secrets are never committed in plaintext; the cluster runs the HashiCorp Vault Secrets Operator
(`apps/vault-operator/`, `components/vault-config/{management,staging,prod}/`).

### Strict rules for agents regarding secrets
1. **Never read secrets in the cluster**: Do **not** run `kubectl get secret`, `kubectl describe
   secret`, or any command that inspects live Kubernetes `Secret` objects or attempts to query Vault
   directly.
2. **Never read `*secret*.yml` / `*secrets*.yml` files in this repo unless explicitly asked to edit
   one**: Even though these files only contain `VaultStaticSecret` CRD references (not secret
   values), filenames matching `*secret*` can trigger permission frameworks that block or reject the
   tool call. Every `VaultStaticSecret` in this repository follows the exact same shape (below), so
   you do not need to read existing `*secret*.yml` files to know what they look like.
3. **Ask the user to add the secret to Vault first, then wait**: Agents cannot and must not add
   secrets to Vault themselves. When a new secret (or secret key) is required:
   - Tell the user the exact Vault path (e.g. `fia/staging/<name>` and `fia/prod/<name>`) and key
     names to add in Vault (`https://secrets.isis.rl.ac.uk`).
   - **Wait for the user to confirm** that the secret has been added to Vault.
   - Only **after** the user confirms it is in Vault, create or update the `VaultStaticSecret` `.yml`
     files (and ensure `VaultAuth`, `VaultConnection`, and ServiceAccount/RBAC bindings exist for
     that namespace in `components/vault-config/<cluster>/`) using the template below:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: <service-or-secret-name>
  namespace: <namespace>
spec:
  type: kv-v2
  refreshAfter: 30s
  vaultAuthRef: static-auth
  mount: fia
  path: fia/<base|staging|prod>/<service-or-secret-name>
  destination:
    name: <k8s-secret-name>
    overwrite: true
    create: true
```

---

## Requirements for manifest changes (GitOps validation & "testing")

In a GitOps repository, there are no unit tests or code-coverage metrics — **rendered Kustomize
output and static manifest checks are your test suite**. Only run Kustomize/linter validation when
YAML manifests are actually changed (skip validation for `.md`-only documentation changes). Before
considering any manifest change complete:

1. **Pull latest `main` before editing**: Because sibling repositories' CI pipelines continuously
   push `[CD] Update ...` commits directly to `main`, always `git pull --ff-only` right before
   making changes so you do not overwrite a newer staging image digest.
2. **Render Kustomize overlays for every affected environment** and verify they build cleanly with
   zero errors:
   ```shell
   kubectl kustomize components/<service>/envs/staging
   kubectl kustomize components/<service>/envs/production
   ```
3. **Diff the rendered `staging` vs. `production` output** whenever touching `base/`, `envs/`, or
   `variants/` to confirm that environment-specific values (e.g. `DEV_MODE`, Vault secret paths,
   hostnames, replica counts) did not leak across environments:
   ```shell
   diff -u \
     <(kubectl kustomize components/<service>/envs/staging) \
     <(kubectl kustomize components/<service>/envs/production)
   ```
4. **Run `kube-linter`** (if installed locally) against the modified component or repo root,
   matching `.github/workflows/lint.yml` and `.kube-linter.yml`:
   ```shell
   kube-linter lint components/<service>
   ```
5. **Verify `prod_release.yml` safety**: Confirm that running the `cp` step from
   `.github/workflows/prod_release.yml` (`envs/staging/<service>.yml` ->
   `envs/production/<service>.yml`) will not clobber any production-only configuration.

---

## Kubernetes & ArgoCD commands

Available kubectl contexts vary per machine/operator (`management`, `staging`, `prod`, or local
clusters) — always run `kubectl config get-contexts` first before targeting a cluster. Never rely on
whatever context is marked current; always pass `--context` explicitly at the **end** of the
command:

```shell
kubectl get applications -n argocd --context <management-context>
kubectl get pods -n fia --context <staging-or-prod-context>
```

Double- and triple-check the context name before running anything against `management` or `prod`.
Never attempt to read or inspect Kubernetes `Secret` resources in any cluster (`kubectl get secret`,
`kubectl describe secret`, etc.). Remember that `selfHeal: true` is enabled on ArgoCD Applications —
do not `kubectl apply` or `kubectl edit` ArgoCD-managed resources directly on `staging` or `prod`;
make the change in this repository instead.

## Managing issues

This repo has no local `.github/ISSUE_TEMPLATE/`; GitHub serves the org-wide default template from
`fiaisis/.github` instead. Always use it rather than inventing an ad hoc issue format:

```shell
gh issue create --template Issue
```

Check `gh issue list` / `gh issue view <number>` first to avoid duplicates.

## Branch naming, commit messages & pull requests

- **Branch naming**: Use `snake_case` descriptions of the work without prefixes like `feature/` or
  `fix/` (note: the automated promotion workflow uses the branch `staging_to_prod`).
- **Commit messages**:
  - `main`'s history (`git log --oneline main`) consists of automated `[CD] Update <service> with
    this commit <url>` commits from sibling repos, promotion commits (`Update <service> from staging
    to prod ...` / `Update prod with staging`), and focused infrastructure commits (e.g. `Update
    Falco chart to 9.2.0 and switch driver to modern_ebpf`).
  - Write clear, imperative-mood commit summaries that state **which component and which
    environment (`staging`, `prod`, `management`, or `base`)** is being changed and why.
  - When inspecting human changes in `git log`, you can filter out automated CD bumps with:
    ```shell
    git log --invert-grep --grep="^\[CD\]" --oneline
    ```
- **Pull request process**:
  1. When YAML manifests are changed (skip for `.md`-only changes), validate with `kubectl kustomize`
     (and `kube-linter` if available) across all affected environments as described in "Requirements
     for manifest changes" above.
  2. **PR title**: normal grammar/sentence case (do not use `snake_case`).
  3. **PR description**: use the org-wide default template from `fiaisis/.github`
     (`Closes # <Issue Number>` + `## Description`; ask the user if no issue number is evident).
  4. **AI-assistance label**: attach a label to the PR indicating that it was made with the
     assistance of AI. Check existing labels first with `gh label list` (e.g. `AI` or `AI_code` in
     this org) and apply the matching label via `gh pr create --label <label>` or
     `gh pr edit <number> --add-label <label>`; if the repo does not have an AI label yet, create
     one first (`gh label create "AI" --description "Created with the assistance of AI"`).

## General working practices

- Prefer the `read` tool (with `offset`/`limit`) over `sed -n`, `cat`, or similar shell one-liners
  when inspecting file contents, and prefer the `write` and `edit` tools over `bash` (`cat <<EOF`,
  `sed -i`, `echo >`), Python one-liners, or other non-tool-based commands whenever creating or
  modifying files.
- **Never read cluster secrets or `*secret*.yml` files**: Do not run `kubectl get/describe secret`
  against any cluster, do not read `*secret*.yml` / `*secrets*.yml` files unless specifically asked
  to edit one, and always ask the user to add any required secret in Vault and wait for their
  confirmation before creating the corresponding `VaultStaticSecret` `.yml` files.
- Ask the user a clarifying question whenever a task is ambiguous — especially whether a change is
  intended for `staging` only, `production` only, or both (`base/`), which cluster (`management`,
  `staging`, `prod`) an Application targets, or what Vault path a new `VaultStaticSecret` should use
  — rather than guessing, since merges to `main` are immediately reconciled onto live clusters by
  ArgoCD.

## Keeping this document up to date

If a change you make would make any information in this `AGENTS.md` inaccurate or incomplete —
e.g. a new ArgoCD Application or component directory, a change to `.github/workflows/prod_release.yml`
or `SERVICES_TO_UPDATE`, a changed Kustomize overlay layout, or a new sibling-repo CD integration —
update the relevant section of this file as part of the same change. Treat it the same way you would
treat `README.md`: documentation that goes stale is worse than no documentation, so don't leave it
to a future agent or PR to notice the drift.
