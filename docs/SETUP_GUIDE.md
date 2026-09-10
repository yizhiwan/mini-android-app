# Setup Guide — mini-android-app CI/CD

Follow these steps in order. Replace `your-github-username`, `mini-android-app-prod`,
and `mini-android-app` with your actual values throughout.

> **Current deployment.** The commands below use `mini-android-app-prod` as a
> generic placeholder project ID. The live pipeline for this repo is actually
> deployed to:
>
> | Resource | Value |
> |---|---|
> | GCP project | `ikhwan-gcp-project` (display name "CICD Portfolio") |
> | GitHub repo | `yizhiwan/mini-android-app` |
> | Build service account | `cloud-build-mini-android@ikhwan-gcp-project.iam.gserviceaccount.com` |
> | PR trigger | `pr-validation` |
> | Post-merge trigger | `post-merge-version-bump` |
>
> Substitute `ikhwan-gcp-project` for `mini-android-app-prod` when running these
> commands against the live setup.

---

## 0. Prerequisites

```bash
gcloud auth login
gcloud config set project mini-android-app-prod
gcloud services enable cloudbuild.googleapis.com secretmanager.googleapis.com
```

Connect Cloud Build to GitHub once, via the Cloud Console (no CLI equivalent
for the initial GitHub App install):

1. Go to **Cloud Build > Triggers > Connect Repository**.
2. Choose **GitHub (Cloud Build GitHub App)**, authenticate, and select the
   `mini-android-app` repository.
3. Install the app with access limited to this one repository.

---

## 1. Generate a GitHub Fine-Grained Personal Access Token (PAT)

This single token is used for both posting PR comments and pushing the
post-merge version bump, so it needs write access to contents and PRs —
nothing else.

1. GitHub → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. **Token name:** `mini-android-app-cloudbuild`
3. **Expiration:** set a reminder to rotate (fine-grained tokens support a
   max of 1 year); 90 days is a reasonable default for a solo project.
4. **Resource owner:** your account (`your-github-username`).
5. **Repository access:** *Only select repositories* → `mini-android-app`.
6. **Permissions** (Repository permissions section):
   - **Contents:** Read and write *(required to push the version-bump commit)*
   - **Pull requests:** Read and write *(required to read PR metadata and post comments)*
   - **Metadata:** Read-only *(mandatory, auto-selected)*
   - Leave everything else at "No access".
7. Generate the token and copy it immediately — GitHub shows it once.

---

## 2. Add the PAT to GCP Secret Manager

Create the (empty) secret container first — this involves no token value:

```bash
gcloud secrets create github-pr-token \
  --project=mini-android-app-prod \
  --replication-policy="automatic"
```

Then add the token as a secret version. Prompt for it rather than passing it as
a command argument, so the token never lands in your shell history. `printf '%s'`
matters here: a trailing newline inside the secret silently breaks the GitHub
`Authorization` header.

```bash
read -rsp "Paste GitHub PAT: " TOKEN && echo && printf '%s' "$TOKEN" | gcloud secrets versions add github-pr-token --project=mini-android-app-prod --data-file=- && unset TOKEN
```

Rotating the token later uses the exact same `versions add` command — each run
adds a new version, and `cloudbuild.yaml` always reads `versions/latest`.

Grant the build service account access to read it.

Note: an organization policy may forbid builds from running as the legacy
default Cloud Build service account, in which case triggers must specify a
user-managed one. Create a dedicated least-privilege account rather than
reusing an existing shared runner:

```bash
gcloud iam service-accounts create cloud-build-mini-android \
  --project=mini-android-app-prod

SA="cloud-build-mini-android@mini-android-app-prod.iam.gserviceaccount.com"

# Required for a build to execute as a user-managed service account
gcloud projects add-iam-policy-binding mini-android-app-prod \
  --member="serviceAccount:${SA}" \
  --role="roles/cloudbuild.builds.builder" \
  --condition=None

# Required because both build configs set options.logging: CLOUD_LOGGING_ONLY
gcloud projects add-iam-policy-binding mini-android-app-prod \
  --member="serviceAccount:${SA}" \
  --role="roles/logging.logWriter" \
  --condition=None

# Scoped to this one secret rather than granted project-wide
gcloud secrets add-iam-policy-binding github-pr-token \
  --project=mini-android-app-prod \
  --member="serviceAccount:${SA}" \
  --role="roles/secretmanager.secretAccessor"
```

---

## 3. Configure Cloud Build triggers

### 3a. PR validation trigger

```bash
gcloud builds triggers create github \
  --project=mini-android-app-prod \
  --name="pr-validation" \
  --repo-owner="your-github-username" \
  --repo-name="mini-android-app" \
  --pull-request-pattern="^main$" \
  --build-config="cloudbuild.yaml" \
  --comment-control="COMMENTS_DISABLED" \
  --substitutions=_GITHUB_OWNER="your-github-username",_GITHUB_REPO="mini-android-app"
```

- `--pull-request-pattern="^main$"` matches PRs whose **base** branch is
  `main`.
- `--comment-control="COMMENTS_DISABLED"` means the build runs
  automatically without requiring a `/gcbrun` comment from a collaborator —
  fine for a solo repo you own. If you ever open the repo to outside
  contributors, switch this to `COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY`.

### 3b. Post-merge version-bump trigger

```bash
gcloud builds triggers create github \
  --project=mini-android-app-prod \
  --name="post-merge-version-bump" \
  --repo-owner="your-github-username" \
  --repo-name="mini-android-app" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild-postmerge.yaml" \
  --substitutions=_GITHUB_OWNER="your-github-username",_GITHUB_REPO="mini-android-app",_REPO_OWNER_NAME="your-github-username",_REPO_OWNER_EMAIL="you@example.com"
```

Set `_REPO_OWNER_NAME` / `_REPO_OWNER_EMAIL` to the identity you want on the
automated bump commits — typically your own name and the email tied to
`ikhwanletter91@gmail.com` or whichever address you commit under normally.

### 3b-i. Gotchas worth knowing

- **The repo must be linked to the project first.** Installing the Cloud Build
  GitHub App on your GitHub account (even with "All repositories" access) is
  *not* sufficient — Cloud Build keeps its own per-project record of which
  repos are connected. Until `mini-android-app` appears under Cloud Build →
  Repositories for this project, both `triggers create github` commands fail
  with a bare `INVALID_ARGUMENT: Request contains an invalid argument.` and no
  further detail. Connect it via Cloud Console → Cloud Build → Triggers →
  Connect Repository, or inline from the Create Trigger form.
- **Pass `--service-account` if an org policy requires one** (see section 2):
  ```
  --service-account="projects/mini-android-app-prod/serviceAccounts/cloud-build-mini-android@mini-android-app-prod.iam.gserviceaccount.com"
  ```
- **Verify the branch regex after creating a trigger from a Windows shell.**
  The leading `^` in `--branch-pattern="^main$"` can be silently eaten by the
  `gcloud.cmd` batch wrapper (`^` is cmd.exe's escape character), leaving the
  pattern as `main$` — which matches *any* branch ending in "main", e.g.
  `release-main`. Check with `gcloud builds triggers describe <name>` and fix
  file-based (shell-free) if needed:
  ```bash
  gcloud beta builds triggers export <name> --destination=trigger.yaml
  # edit the branch: field, then
  gcloud beta builds triggers import --source=trigger.yaml
  ```

### 3c. Verify

```bash
gcloud builds triggers list --project=mini-android-app-prod
```

Open a throwaway PR and confirm the `pr-validation` trigger fires and posts
a status check named **`pr-validation`** (or similar — Cloud Build derives
the GitHub status-check context name from the trigger name) on the PR. You
need at least one build to have run before this check name is selectable in
GitHub's branch protection UI (step 4 below).

---

## 3d. Builder image

Google publishes no official Android builder image, and the commonly cited
community ones are a trap: `cirrusci/android-sdk` stops at tag `33`, and
`cimg/android` ships JDK 21 and runs as a non-root user, which breaks writes
to Cloud Build's `/workspace`. Referencing an image tag that does not exist
fails the build *before any step runs*, so the failure-notification step never
fires and no PR comment appears — the build just dies pulling.

This repo therefore builds its own image from
[`.cloudbuild/builder/Dockerfile`](../.cloudbuild/builder/Dockerfile):
JDK 17 + Android SDK 34, everything pinned, hosted in Artifact Registry in the
same region as the builds that pull it.

Create the registry and seed the first image:

```bash
gcloud services enable artifactregistry.googleapis.com --project=mini-android-app-prod

gcloud artifacts repositories create android-builders \
  --project=mini-android-app-prod \
  --repository-format=docker \
  --location=us-central1

gcloud builds submit .cloudbuild/builder \
  --project=mini-android-app-prod \
  --tag=us-central1-docker.pkg.dev/mini-android-app-prod/android-builders/android-sdk:34 \
  --timeout=1800s

gcloud artifacts repositories add-iam-policy-binding android-builders \
  --project=mini-android-app-prod \
  --location=us-central1 \
  --member="serviceAccount:cloud-build-mini-android@mini-android-app-prod.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

After that, a third trigger rebuilds it automatically whenever the Dockerfile
changes — and *only* then, thanks to the included-files filter:

```bash
gcloud builds triggers create github \
  --project=mini-android-app-prod \
  --name="builder-image-rebuild" \
  --repo-owner="your-github-username" \
  --repo-name="mini-android-app" \
  --branch-pattern="^main$" \
  --build-config=".cloudbuild/builder/cloudbuild.yaml" \
  --included-files=".cloudbuild/builder/**" \
  --service-account="projects/mini-android-app-prod/serviceAccounts/cloud-build-mini-android@mini-android-app-prod.iam.gserviceaccount.com"
```

### Keeping image storage free

The image uses a **moving `:34` tag**, not immutable per-build tags.
Reproducibility comes from the pinned Dockerfile in git, not from retaining
old image versions in paid storage. A cleanup policy deletes untagged versions
(the ones orphaned by each rebuild) after 7 days, which holds the repository
at roughly one version — about 480 MB, inside Artifact Registry's 0.5 GB
always-free tier:

```bash
cat > /tmp/cleanup-policy.json <<'EOF'
[
  {
    "name": "delete-untagged-after-7d",
    "action": { "type": "Delete" },
    "condition": { "tagState": "UNTAGGED", "olderThan": "7d" }
  }
]
EOF

gcloud artifacts repositories set-cleanup-policies android-builders \
  --project=mini-android-app-prod \
  --location=us-central1 \
  --policy=/tmp/cleanup-policy.json \
  --no-dry-run
```

Without that policy the orphaned versions accumulate silently and push the
repository past the free tier.

---

## 4. GitHub branch protection on `main`

GitHub → repo → **Settings → Branches → Add branch protection rule**.

- **Branch name pattern:** `main`
- ☑ **Require a pull request before merging**
  - ☑ Require approvals — set to `0` if you're the sole reviewer, or keep
    the review requirement off entirely for a solo repo; approvals from a
    single-contributor account otherwise deadlock (you can't approve your
    own PR by default).
- ☑ **Require status checks to pass before merging**
  - ☑ Require branches to be up to date before merging
  - In the search box, select the check produced by the `pr-validation`
    trigger (visible only after step 3c's throwaway PR has run once). Cloud
    Build reports through GitHub's Checks API, and the check is named
    `<trigger-name> (<gcp-project-id>)` — for the live setup that is
    `pr-validation (ikhwan-gcp-project)`. Querying the legacy
    `/commits/{sha}/status` endpoint shows `pending` forever and is the wrong
    place to look; use `/commits/{sha}/check-runs`.
- ☑ **Require conversation resolution before merging** *(optional, recommended)*
- ☐ **Do not allow bypassing the above settings** — **leave this unchecked**.
  `bump-version.sh` pushes directly to `main` using your PAT, which is tied
  to your (admin) account. If you check "do not allow bypassing", that
  direct push will itself be blocked by the "require PR" rule. Leaving it
  unchecked lets repository admins (you) bypass the PR requirement for
  direct pushes, while collaborators without admin rights still go through
  the full PR + status-check flow.
- ☐ Do not enable "Restrict who can push to matching branches" unless you
  explicitly want to exclude your own account from the bypass above.

Save the rule, then re-verify with the same throwaway PR: it should be
blocked from merging until the `pr-validation` check turns green, and after
merging you should see an automated `chore: bump version to ... [skip ci]`
commit land on `main` within a few minutes.

---

## 5. Cost notes

- Cloud Build's always-free tier covers **120 build-minutes/day** on the
  `E2_MEDIUM` machine type used by both pipelines here — see
  `docs/ARCHITECTURE.md` for why `E2_STANDARD_2` (as originally specified)
  isn't a valid Cloud Build machine type.
- Secret Manager's free tier covers 6 active secret versions and 10,000
  access operations/month, well above what a solo repo's two triggers will
  generate.
- Artifact storage (`gs://mini-android-app-prod-cloudbuild-artifacts/...` in
  `cloudbuild.yaml`) is **not** free — Cloud Storage bills for stored bytes
  past the "Always Free" 5 GB threshold. Create the bucket with a lifecycle
  rule to auto-delete old PR-check artifacts if you want to stay
  comfortably inside the free tier:

  ```bash
  gcloud storage buckets create gs://mini-android-app-prod-cloudbuild-artifacts \
    --project=mini-android-app-prod \
    --location=us-central1

  cat > /tmp/lifecycle.json <<'EOF'
  {"rule": [{"action": {"type": "Delete"}, "condition": {"age": 14}}]}
  EOF

  gcloud storage buckets update gs://mini-android-app-prod-cloudbuild-artifacts \
    --lifecycle-file=/tmp/lifecycle.json

  gcloud storage buckets add-iam-policy-binding gs://mini-android-app-prod-cloudbuild-artifacts \
    --member="serviceAccount:cloud-build-mini-android@mini-android-app-prod.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin"
  ```

  Create this bucket **before** the first PR build. `cloudbuild.yaml`'s
  `artifacts` block fails the whole build if the destination bucket is
  missing — so a PR with passing tests would still report a red status check.
  Keep the bucket in a US region: GCS's always-free 5 GB applies to
  `us-central1`/`us-east1`/`us-west1` only, not to `asia-*`.
