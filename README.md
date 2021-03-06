
Now support uploading to a local debian repository
Install reprepro package and do man reprepro and look at files under
samples/local_repository_config for information
Also look at: https://wiki.debian.org/DebianRepository/SetupWithReprepro

Removed bintray-related files - bintray Debian repos don't get
signed properly / automatically so far.

Now dominant way to use is using config:
    ~/.kernel_build_config
Look at samples/sample_kernel_build.config for an annotated example
Can still use environment variables, but number of variables
have increased and will be clumsy.

If you are ONLY building kernel locally, and do NOT want:
    - Source debs for uploading to Launchpad
    - Creation of metapackages
    - Uploading to local repo
then do one of the following:

    1. Continue as before, but add KERNEL__NO_SRC_PKG=yes to
       environment variables

    2. Start a minimal config and make sure you set:
       KERNEL__NO_SRC_PKG=yes    - avoid building source packages
       unset METAPKG_BUILD_DIR   - avoid building metapackages
       unset LOCAL_DEB_REPO_DIR  - avoid uploading to local repo

If you _DO_ want to build metapackages, the metapackages are
automatically built when you call patch_and_build_kernel.sh
RIGHT AT THE BEGINNING, so that you can enter the passphrase
as early as possible, instead of waiting for the kernel download
and compilation to finish.

Sequence:

    1. Run patch_and_build_kernel.sh
    2. Run local_upload.sh - if desired
    3. Run ppa_upload.sh - if desired

### Download and build Linux kernel source from kernel.org
- Has 'one-touch' default behavior
- Behavior can be customized using environment variables

### DEFAULT behavior:
- Kernel source is downloaded and built in CURRENT DIRECTORY (not necessarily where patch_and_build_kernel.sh is)
- Will automatically download and build the LATEST kernel
- Will automatically upgrade kernel config when moving to next major version
    - For new config entries:
        - Anything that can become a module will be modularized
        - Everything else gets the DEFAULT value
- DEBS will be built in a sub-directory named 'debs' under CURRENT DIRECTORY (not necessarily where patch_and_build_kernel.sh is)
- The 'debs' directory will be deleted and re-created if it exists
- Will use config.kernel in the directory patch_and_build_kernel.sh is
- Defaults to using (available_cores -1) cores
- config.prefs in directory where patch_and_build_kernel.sh is can contain name=value pairs that will be applied to the config while building

### Things that can be changed using environment variables:
See samples/sample_kernel.config for a list of environment variables that can be set, their default values and meanings

The additional environment variable KERNEL_BUILD_CONFIG can be set to point at the config file to be sourced - defaults to ~/.kernel_build.config.

If you are uploading to bintray, see samples/sample_bintray.config for a list of environment variables that MUST be set for upload to work.

The additional environment variable BINTRAY_CONFIG can be set to point at bintray config file to source - defaults to ~/.bintray.config

### config.prefs or KERNEL_CONFIG_PREFS format:
- Lines starting with '#' are ignored
- Blank lines are ignored
- Valid lines should contain:
    name=value OR
    name = value
- Regex is '^\s*(?P<KEY>\S+)\s*=\s*(?P<VAL>\S+)'

### Packages required:
- Run required_pkgs.sh in this directory to check and report missing packages
- patch_and_build_kernel.sh automatically calls this when it runs
