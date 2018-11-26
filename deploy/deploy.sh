#!/bin/bash -l

# This script assumes that the following variables are set in the environment:
#
# DEPLOYMENT_ROOT: path to deploy to

set -o errexit
set -o nounset

DEFAULT_DEPLOYMENT_ROOT="/gpfs/bbp.cscs.ch/apps/hpc/test/$(whoami)/deployment"
DEFAULT_DEPLOYMENT_DATA="/gpfs/bbp.cscs.ch/data/project/proj20/pramod_scratch/SPACK_DEPLOYMENT/download"
DEFAULT_DEPLOYMENT_DATE="$(date +%Y-%m-%d)"

# Set variables to default. The user may override the following:
#
# * `DEPLOYMENT_ROOT` for the installation directory
# * `DEPLOYMENT_DATA` containing tarballs of proprietary software
# * `DEPLOYMENT_DATE` to force a date for the installation directory
#
# for the latter, see also the comment of `last_install_dir`
DEPLOYMENT_DATA=${DEPLOYMENT_DATA:-${DEFAULT_DEPLOYMENT_DATA}}
DEPLOYMENT_ROOT=${DEPLOYMENT_ROOT:-${DEFAULT_DEPLOYMENT_ROOT}}
SPACK_MIRROR_DIR="${DEPLOYMENT_ROOT}/mirror"
export DEPLOYMENT_ROOT SPACK_MIRROR_DIR

# A list of stages in the order they will be built
stages="compilers tools serial-libraries parallel-libraries applications"

# Definitions for the installation spec generation. For every stage
# mentioned above, this should be a list of filenames *without* extension
# found in `packages`.
declare -A spec_definitions=([compilers]=compilers
                             [tools]=tools
                             [serial-libraries]="serial-libraries python-packages"
                             [parallel-libraries]=parallel-libraries
                             [applications]=bbp-packages)

# Set up the dependency graph
declare -A spec_parentage
last=""
for stage in $stages; do
    if [[ -n "$last" ]]; then
        spec_parentage[$stage]="$last"
    fi
    last="$stage"
done

log() {
    echo "$(tput bold)### $@$(tput sgr0)" >&2
}

install_dir() {
    # Create an installation directory based on the environment variables
    # set.
    what=$1
    date="${DEPLOYMENT_DATE:-${DEFAULT_DEPLOYMENT_DATE}}"
    name="${DEPLOYMENT_ROOT}/install/${what}/${date}"
    if [[ -L "${name}" ]]; then
        echo "$(readlink -f ${name})"
    else
        echo "${name}"
    fi
}

last_install_dir() {
    # Obtain the installation directory of a parental stage, i.e.,
    # compilers when building tools. Based on some assumptions:
    #
    # 1. Attempt to use the globally set `DEPLOYMENT_DATE` or default via
    #    `install_dir`
    # 2. Otherwise, use the latest directory present
    what=$1
    name="$(install_dir ${what})"
    if [[ ! -d "${name}" ]]; then
        name=$(find "${DEPLOYMENT_ROOT}/install/${what}" -mindepth 1 -maxdepth 1 -type d|sort|tail -n1)
    fi
    echo "$(readlink -f ${name})"
}

configure_compilers() {
    while read -r line; do
        set +o nounset
        spack load ${line}
        set -o nounset
        if [[ ${line} != *"intel-parallel-studio"* ]]; then
            spack compiler find --scope=user
        fi

        if [[ ${line} = *"intel"* ]]; then
            GCC_DIR=$(spack location --install-dir gcc@6.4.0)

            # update intel modules to use gcc@6.4.0 in .cfg files
            install_dir=$(spack location --install-dir ${line})
            for f in $(find ${install_dir} -name "icc.cfg" -o -name "icpc.cfg" -o -name "ifort.cfg"); do
                if ! grep -q "${GCC_DIR}" $f; then
                    echo "-gcc-name=${GCC_DIR}/bin/gcc" >> ${f}
                    echo "-Xlinker -rpath=${GCC_DIR}/lib" >> ${f}
                    echo "-Xlinker -rpath=${GCC_DIR}/lib64" >> ${f}
                    log "updated ${f} with newer GCC"
                fi
            done
        elif [[ ${line} = *"pgi"* ]]; then
            #update pgi modules for network installation
            PGI_DIR=$(dirname $(which makelocalrc))
            makelocalrc ${PGI_DIR} -gcc ${GCC_DIR}/bin/gcc -gpp ${GCC_DIR}/bin/g++ -g77 ${GCC_DIR}/bin/gfortran -x -net

            #configure pgi network license
            template=$(find $PGI_DIR -name localrc* | tail -n 1)
            for node in bbpv1 bbpv2 bbptadm tds03 tds04 r2i3n0 r2i3n1 r2i3n2 r2i3n3 r2i3n4 r2i3n5 r2i3n6; do
                cp $template $PGI_DIR/localrc.$node || true
            done
        fi
        spack unload ${line}
    done

    sed  -i 's#.*f\(77\|c\): null#      f\1: /usr/bin/gfortran#' ${HOME}/.spack/compilers.yaml
}

populate_mirror() {
    what=$1
    log "populating mirror for ${what}"

    specfile="$(install_dir ${what})/data/specs.txt"
    spec_list=$(spack filter --not-installed $(cat ${specfile}))

    if [[ -z "${spec_list}" ]]; then
        log "...found no new packages"
        return 0
    fi

    if [[ "${what}" = "compilers" ]]; then
        for compiler in intel intel-parallel-studio pgi; do
            mkdir -p ${SPACK_MIRROR_DIR}/${compiler}
            cp ${DEPLOYMENT_DATA}/${compiler}/* ${SPACK_MIRROR_DIR}/${compiler}/
        done
    fi

    log "found the following specs"
    echo "${spec_list}"
    spack mirror create -D -d ${SPACK_MIRROR_DIR} ${spec_list}
    spack mirror add --scope=user my_mirror ${SPACK_MIRROR_DIR} || log "mirror already added!"
}

filter_specs() {
    package_list=$1
    cat ${package_list}
    # spack filter --not-installed $(<${package_list})
}

check_specs() {
    spack spec -Il "$@"
}

generate_specs() {
    what="$@"

    if [[ -z "${what}" ]]; then
        log "asked to generate no specs!"
        return 1
    fi

    venv="${DEPLOYMENT_ROOT}/deploy/venv"

    log "updating the deployment virtualenv"
    # Recreate the virtualenv and update the command line
    mkdir -p ${venv}
    virtualenv -q -p $(which python) ${venv} --clear
    set +o nounset
    . ${venv}/bin/activate
    set -o nounset
    pip install -q --force-reinstall -U .

    for stage in ${what}; do
        log "generating specs for ${stage}"
        datadir="$(install_dir ${stage})/data"

        mkdir -p "${datadir}"
        env &> "${datadir}/spack_deploy.env"
        git rev-parse HEAD &> "${datadir}/spack_deploy.version"

        rm -f "${datadir}/specs.txt"
        for stub in ${spec_definitions[$stage]}; do
            log "...using ${stub}.yaml"
            spackd --input packages/${stub}.yaml packages x86_64 >> "${datadir}/specs.txt"
        done
    done
}

copy_configuration() {
    what="$1"

    log "copying configuration"
    log "...into ${HOME}"
    rm -rf "${HOME}/.spack"
    mkdir -p "${HOME}/.spack"
    cp configs/*.yaml "${HOME}/.spack"

    if [[ ${spec_parentage[${what}]+_} ]]; then
        parent="${spec_parentage[$what]}"
        pdir="$(last_install_dir ${parent})"
        log "...using configuration output of ${parent}"
        cp "${pdir}/data/packages.yaml" "${HOME}/.spack"
        cp "${pdir}/data/compilers.yaml" "${HOME}/.spack"
    fi

    if [[ -d "configs/${what}" ]]; then
        log "...using specialized configuration files: $(ls configs/${what})"
        cp configs/${what}/*.yaml "${HOME}/.spack"
    fi
}

install_specs() {
    what="$1"

    location="$(install_dir ${what})"
    HOME="${location}/data"
    SOFTS_DIR_PATH="${location}"
    MODS_DIR_PATH="${location}/modules"
    export HOME SOFTS_DIR_PATH MODS_DIR_PATH

    copy_configuration "${what}"

    # This directory may fail intel builds, pre-emptively remove it.
    rm -rf "${HOME}/intel/.pset"

    log "sourcing spack environment"
    . ${DEPLOYMENT_ROOT}/deploy/spack/share/spack/setup-env.sh
    env &> "${HOME}/spack.env"
    (cd "${DEPLOYMENT_ROOT}/deploy/spack" && git rev-parse HEAD) &> "${HOME}/spack.version"

    populate_mirror "${what}"

    log "gathering specs"
    spec_list=$(spack filter --not-installed $(< ${HOME}/specs.txt))

    if [[ "${spec_list}" == *[[:space:]]* ]]; then
        log "found the following uninstalled specs"
        echo "${spec_list}"
        log "...checking specs"
        spack spec -Il ${spec_list}
    fi

    log "running installation for all specs"
    spack install -y --log-format=junit --log-file="${HOME}/stack.xml" $(< "${HOME}/specs.txt")

    if [[ "${what}" = "serial-libraries" ]]; then
        while read spec; do
            if [[ "${spec}" = py-* ]]; then
                spack activate $spec
            fi
        done <<< "${spec_list}"
    fi

    mkdir -p "${WORKSPACE:-.}/stacks"
    cp "${HOME}/stack.xml" "${WORKSPACE:-.}/stacks/${what}.xml"

    spack module tcl refresh -y
    . ${DEPLOYMENT_ROOT}/deploy/spack/share/spack/setup-env.sh
    spack export --scope=user --explicit > "${HOME}/packages.yaml"

    if [[ "${what}" = "compilers" ]]; then
        cp configs/packages.yaml ${HOME}/packages.yaml
        if [[ -n "${spec_list}" ]]; then
            log "adding compilers"
            configure_compilers < "${HOME}/specs.txt"
        fi
    fi

    cp "${HOME}/.spack/compilers.yaml" "${HOME}" || true
}

usage() {
    echo "usage: $0 [-gi] stage...1>&2"
    exit 1
}

do_generate=default
do_install=default
while getopts "gi" arg; do
    case "${arg}" in
        g)
            do_generate=yes
            [[ ${do_install} = "default" ]] && do_install=no
            ;;
        i)
            do_install=yes
            [[ ${do_generate} = "default" ]] && do_generate=no
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ "$@" = "all" ]]; then
    set -- ${stages}
else
    unknown=
    for what in "$@"; do
        if [[ ! ${spec_definitions[${what}]+_} ]]; then
            unknown="${unknown} ${what}"
        fi
    done
    if [[ -n "${unknown}" ]]; then
        echo "unknown stage(s):${unknown}"
        echo "allowed:          ${stages}"
        exit 1
    fi
fi

declare -A desired
for what in "$@"; do
    desired[${what}]=Yes
done

unset $(set +x; env | awk -F= '/^(PMI|SLURM)_/ {print $1}' | xargs)

[[ ${do_generate} != "no" ]] && generate_specs "$@"
for what in ${stages}; do
    if [[ ${desired[${what}]+_} && ${do_install} != "no" ]]; then
        install_specs ${what}
    fi
done
