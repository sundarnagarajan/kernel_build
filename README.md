Download and build Linux kernel source from kernel.org
- Has 'one-touch' default behavior
- Behavior can be customized using environment variables

### DEFAULT behavior:
- Kernel source is downloaded and built in directory where this script is
- Will automatically download and build the LATEST kernel
- Will automatically upgrade kernel config when moving to next major version
    - For new config entries:
        - Anything that can become a module will be modularized
        - Everything else gets the DEFAULT value
- DEBS will be built in a sub-directory named 'debs' under the directory where this script is
- The 'debs' directory will be deleted and re-created if it exists
- Will use config.kernel in the directory where this script is
- Defaults to using as many threads as available cores
- config.prefs in directory where this script is can contain name=value pairs that will be applied to the config while building

### Things that can be changed using environment variables:
#### KERNEL_TYPE:  
    - Will filter available kernels
    - IGNORED if it is not a recognized type: latest|mainline|stable|longterm

#### KERNEL_VERSION:
    - Will override version from config file
    - Will filter available kernels

#### KERNEL_CONFIG:
    - FULL PATH to existing config file
    - Will override config.kernel in this directory

#### KERNEL_BUILD_DIR:
    - Overrides current_dir/debs
    - All path components except the last one MUST exist
    - If last path ocmponent does not exist, it is created
    - If last path component exists, all files/dirs under that path are DELETED

#### NUM_THREADS:
    - Number of threads to use

#### KERNEL_CONFIG_PREFS: 
    - FULL path to file containing name=value pairs that will be applied to the config while building
    - See config.prefs format below

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