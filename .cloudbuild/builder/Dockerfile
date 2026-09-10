# Android builder image for Cloud Build.
#
# Google publishes no official Android builder image, and the widely-cited
# community images either lag the SDK level we target, run as a non-root user
# (which breaks writes to Cloud Build's /workspace), or are large enough that
# pulling them dominates build time. Building our own keeps the image small,
# pinned, and in the same region as the builds that pull it.
#
# Rebuild and push with:
#   gcloud builds submit .cloudbuild/builder \
#     --tag us-central1-docker.pkg.dev/PROJECT_ID/android-builders/android-sdk:34

FROM eclipse-temurin:17-jdk-jammy

# cmdline-tools v12. Pinned deliberately: "latest" in the filename refers to
# the channel, not the version, so an unpinned URL silently changes the SDK
# tooling underneath the build.
ARG CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_PLATFORM=34
ARG BUILD_TOOLS_VERSION=34.0.0

ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="${PATH}:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        unzip \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip

RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install \
        "platform-tools" \
        "platforms;android-${ANDROID_PLATFORM}" \
        "build-tools;${BUILD_TOOLS_VERSION}" > /dev/null \
    && rm -rf "${ANDROID_SDK_ROOT}/.temp" /root/.android

WORKDIR /workspace
