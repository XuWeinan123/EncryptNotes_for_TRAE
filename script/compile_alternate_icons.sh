#!/bin/sh

set -eu

output_root="${DERIVED_FILE_DIR}/SealNoteAlternateIcons"
resources_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

mkdir -p "${output_root}" "${resources_dir}"

for icon_name in Icon2 Icon3; do
    icon_output="${output_root}/${icon_name}"
    partial_plist="${output_root}/${icon_name}.plist"

    mkdir -p "${icon_output}"

    "${DEVELOPER_DIR}/usr/bin/actool" \
        "${SRCROOT}/SealNote/${icon_name}.icon" \
        --compile "${icon_output}" \
        --output-format human-readable-text \
        --output-partial-info-plist "${partial_plist}" \
        --app-icon "${icon_name}" \
        --target-device mac \
        --minimum-deployment-target "${MACOSX_DEPLOYMENT_TARGET}" \
        --platform macosx

    install -m 0644 "${icon_output}/${icon_name}.icns" "${resources_dir}/${icon_name}.icns"
done
