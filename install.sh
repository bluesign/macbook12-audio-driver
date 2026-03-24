#!/bin/bash
#
# MacBook 8,1 Audio Driver - Build & Install Script
# Downloads matching kernel source, patches the Cirrus codec, builds, and installs.
#

set -e

while [ $# -gt 0 ]; do
    case $1 in
        -i|--install) dkms_action='install';;
        -k|--kernel)  dkms_kernel=$2; shift;;
        -r|--remove)  dkms_action='remove';;
        -u|--uninstall) dkms_action='remove';;
        (-*) echo "Unknown option: $1" >&2; exit 1;;
        (*) break;;
    esac
    shift
done

if [[ $dkms_action == 'install' ]]; then
    bash dkms-helper.sh
    exit
elif [[ $dkms_action == 'remove' ]]; then
    bash dkms-helper.sh -r
    exit
fi

[[ -n $dkms_kernel ]] && uname_r=$dkms_kernel || uname_r=$(uname -r)
kernel_version=$(echo "$uname_r" | cut -d '-' -f1 | cut -d '_' -f1)

major_version=$(echo "$kernel_version" | cut -d '.' -f1)
minor_version=$(echo "$kernel_version" | cut -d '.' -f2)

build_dir="build"
patch_dir="patch_cirrus"
hda_dir="$build_dir/hda"

[[ -d $hda_dir ]] && rm -rf "$hda_dir"
[[ ! -d $build_dir ]] && mkdir "$build_dir"

# Download kernel source
wget -c "https://cdn.kernel.org/pub/linux/kernel/v${major_version}.x/linux-${kernel_version}.tar.xz" -P "$build_dir" || {
    kernel_version="${major_version}.${minor_version}"
    wget -c "https://cdn.kernel.org/pub/linux/kernel/v${major_version}.x/linux-${kernel_version}.tar.xz" -P "$build_dir" || {
        echo "ERROR: Could not download kernel source" >&2
        exit 1
    }
}

# Clean old tarballs
find "$build_dir/" -maxdepth 1 -name 'linux-*.tar.xz' ! -name "linux-${kernel_version}.tar.xz" -delete

if (( major_version > 6 || (major_version == 6 && minor_version >= 17) )); then
    # Kernel 6.17+: sound/hda layout
    tar --strip-components=2 -xf "$build_dir/linux-${kernel_version}.tar.xz" \
        --directory="$build_dir/" "linux-${kernel_version}/sound/hda"

    mv "$hda_dir/codecs/cirrus/Makefile" "$hda_dir/codecs/cirrus/Makefile.orig"
    mv "$hda_dir/codecs/cirrus/cs420x.c" "$hda_dir/codecs/cirrus/cs420x.c.orig"

    cp "$patch_dir/cs420x.c" \
       "$patch_dir/patch_cirrus.c" \
       "$patch_dir/patch_cirrus_a1534_setup.h" \
       "$patch_dir/patch_cirrus_a1534_pcm.h" \
       "$patch_dir/patch_cirrus_macbook81_setup.h" \
       "$hda_dir/codecs/cirrus/"

    cp "$patch_dir/Makefile_cs420x" "$hda_dir/codecs/cirrus/Makefile"
else
    # Kernel < 6.17: sound/pci/hda layout
    tar --strip-components=3 -xf "$build_dir/linux-${kernel_version}.tar.xz" \
        --directory="$build_dir/" "linux-${kernel_version}/sound/pci/hda"

    mv "$hda_dir/Makefile" "$hda_dir/Makefile.orig"
    mv "$hda_dir/patch_cirrus.c" "$hda_dir/patch_cirrus.c.orig"

    cp "$patch_dir/patch_cirrus.c" \
       "$patch_dir/patch_cirrus_a1534_setup.h" \
       "$patch_dir/patch_cirrus_a1534_pcm.h" \
       "$patch_dir/patch_cirrus_macbook81_setup.h" \
       "$hda_dir/"

    cp "$patch_dir/Makefile_cirrus" "$hda_dir/Makefile"

    # Pre-6.17: .free instead of .remove
    sed -i 's/\.remove/.free/' "$hda_dir/patch_cirrus_a1534_pcm.h"
fi

# Kernel 6.12-6.16: snd_pci_quirk -> hda_quirk rename
if (( major_version == 6 && minor_version >= 12 && minor_version < 17 )); then
    target="$hda_dir/patch_cirrus.c"
    sed -i 's/snd_pci_quirk/hda_quirk/' "$target"
    sed -i 's/SND_PCI_QUIRK\b/HDA_CODEC_QUIRK/' "$target"
fi

# Kernel <= 6.11: keep old names
if (( major_version == 6 && minor_version <= 11 )); then
    target="$hda_dir/patch_cirrus.c"
    sed -i 's/hda_quirk/snd_pci_quirk/' "$target"
fi

# Build and install
update_dir="/lib/modules/$(uname -r)/updates"
[[ ! -d $update_dir ]] && mkdir -p "$update_dir"

make
make install

echo ""
echo "Installed. Contents of $update_dir:"
ls -lA "$update_dir"
