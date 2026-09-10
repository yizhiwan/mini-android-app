# Setup Guide — mini-android-app CI/CD

Follow these steps in order. Replace `your-github-username`, `mini-android-app-prod`,
and `mini-android-app` with your actual values throughout.

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

```bash
printf '%s' 'ghp_yourFineGrainedTokenHere' | gcloud secrets create github-pr-token \
  --project=mini-android-app-prod \
  --replication-policy="automatic" \
  --data-file=-
```

If the secret already exists and you're rotating it:

```bash
printf '%s' 'ghp_yourNewTokenHere' | gcloud secrets versions add github-pr-token \
  --project=mini-android-app-prod \
  --data-file=-
```

Grant the Cloud Build service account access to read it:

```bash
PROJECT_NUMBER=$(gcloud projects describe mini-android-app-prod --format='value(projectNumber)')

gcloud secrets add-iam-policy-binding github-pr-token \
  --project=mini-android-app-prod \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
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
    trigger (visible only after step 3c's throwaway PR has run once).
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
  ```
