#!/bin/sh
set -eu

RESOURCE_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
PLIST_PATH="${RESOURCE_DIR}/PicaXBuildEnvironment.plist"

mkdir -p "${RESOURCE_DIR}"
/usr/bin/plutil -create xml1 "${PLIST_PATH}"

command_output() {
    "$@" 2>/dev/null || true
}

first_non_empty() {
    for value in "$@"; do
        if [ -n "${value}" ]; then
            printf '%s' "${value}"
            return
        fi
    done
}

set_string() {
    /usr/bin/plutil -replace "$1" -string "$2" "${PLIST_PATH}"
}

host_name="$(command_output /bin/hostname)"
if [ -z "${host_name}" ]; then
    host_name="unknown"
fi

os_name="$(command_output /usr/bin/sw_vers -productName)"
os_version="$(command_output /usr/bin/sw_vers -productVersion)"
os_build="$(command_output /usr/bin/sw_vers -buildVersion)"
if [ -z "${os_name}" ]; then
    os_name="macOS"
fi
if [ -z "${os_version}" ]; then
    os_version="unknown"
fi
if [ -z "${os_build}" ]; then
    os_build="unknown"
fi

xcode_version="$(/usr/bin/xcodebuild -version 2>/dev/null | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/[[:space:]]*$//')"
if [ -z "${xcode_version}" ]; then
    xcode_version="unknown"
fi

build_commit="$(first_non_empty \
    "${PICAX_BUILD_COMMIT:-}" \
    "${PICA_X_BUILD_COMMIT:-}" \
    "${BUILD_COMMIT:-}" \
    "${CI_COMMIT:-}" \
    "${GITHUB_SHA:-}" \
    "${CI_COMMIT_SHA:-}" \
    "${GIT_COMMIT:-}" \
    "${CM_COMMIT:-}" \
    "${FCI_COMMIT:-}" \
    "${BUILD_SOURCEVERSION:-}" \
    "${DRONE_COMMIT_SHA:-}" \
    "${SEMAPHORE_GIT_SHA:-}" \
    "${BUDDY_EXECUTION_REVISION:-}" \
    "${BITRISE_GIT_COMMIT:-}" \
    "${CIRCLE_SHA1:-}" \
    "${BUILDKITE_COMMIT:-}" \
    "${CODEBUILD_RESOLVED_SOURCE_VERSION:-}" \
    "${APPVEYOR_REPO_COMMIT:-}" \
    "${TRAVIS_COMMIT:-}" \
)"
if [ -z "${build_commit}" ] && [ -n "${SRCROOT:-}" ]; then
    build_commit="$(command_output /usr/bin/git -C "${SRCROOT}" rev-parse HEAD)"
fi
if [ -z "${build_commit}" ]; then
    build_commit="unknown"
fi

build_commit_short="${build_commit}"
if [ "${build_commit}" != "unknown" ]; then
    build_commit_short="$(printf '%s' "${build_commit}" | /usr/bin/cut -c 1-12)"
fi

set_string BuildTime "$(/bin/date '+%Y-%m-%d %H:%M:%S %z')"
set_string BuildCommit "${build_commit_short}"
set_string BuildCommitFull "${build_commit}"
set_string BuildHostName "${host_name}"
set_string BuildUser "${USER:-unknown}"
set_string BuildHostOS "${os_name} ${os_version} (${os_build})"
set_string BuildHostArchitecture "$(command_output /usr/bin/uname -m)"
set_string BuildXcode "${xcode_version}"
