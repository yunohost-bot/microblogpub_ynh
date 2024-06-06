#!/bin/bash

python_version=3.10.6                                   # python version to be installed by pyenv
microblogpub_app="$install_dir/app"                     # path to microblog.pub istself
microblogpub_venv="$install_dir/venv"                   # path to microblog.pubs venvsa
microblogpub_src_pyenv="$install_dir/pyenv.src"         # path to microblog.pubs pyenv sources
microblogpub_pyenv="$install_dir/pyenv"                 # path to microblog.pubs python version
microblogpub_bin_pyenv="${microblogpub_pyenv}/versions/${python_version}/bin" # pyenv exectutablesa
microblogpub_active_venv='not_found'                    # initialize path to active venv
fpm_usage=medium

microblogpub_set_active_venv() {
    # poetry installs the venv to a path that cannot be given to it
    # https://github.com/python-poetry/poetry/issues/2003
    # we set the path to the active venv installed through poetry by
    # using the apropriate poetry command: `env info --path`
    microblogpub_active_venv=$(
        export PATH="${microblogpub_bin_pyenv}:$PATH"
        export POETRY_VIRTUALENVS_PATH=${microblogpub_venv}
        cd ${microblogpub_app}
        poetry env info --path
    )
}

microblogpub_set_filepermissions() {
    local dir
    chmod 750 "$install_dir" "$data_dir"
    chmod -R o-rwx "$install_dir" "$data_dir"
    chown -R $app:www-data "$install_dir" "$data_dir"
    chmod u+x $install_dir/inv.sh
    chown -R $app:www-data "/var/log/$app"
}

microblogpub_install_python() {
    # Install/update pyenv
    ynh_setup_source --dest_dir="${microblogpub_src_pyenv}" --source_id=pyenv
    export PYENV_ROOT=${microblogpub_pyenv}

    if [ -d "${microblogpub_pyenv}/versions" ]; then
        local old_python_version=`ls ${microblogpub_pyenv}/versions`
        if [ ! -z "${old_python_version}" ]; then
            if [ "${old_python_version}" != "${python_version}" ]; then
                local old_python_version_path="${microblogpub_pyenv}/versions/${old_python_version}"
                if [ -d "${old_python_version_path}" ]; then
                    ynh_print_info --message="Deleting Python ${old_python_version}"
                    ynh_secure_remove --file="${old_python_version_path}"
                fi
            fi
        fi
    fi

    if [ ! -d "${microblogpub_pyenv}/versions/${python_version}" ]; then
        ynh_print_info --message="Installing Python ${python_version}"
        ${microblogpub_src_pyenv}/bin/pyenv install $python_version
        ynh_app_setting_set --app=$YNH_APP_INSTANCE_NAME --key=python_version --value=$python_version
    else
        ynh_print_info --message="Python ${python_version} is already installed"
    fi 
}

microblogpub_install_deps () {
    ynh_print_info --message="Installing deps with poetry"
    (
        export PATH="${microblogpub_bin_pyenv}:$PATH"
		# pip and poetry run from the above set pyenv path and knows where to install packages
        pip install poetry
        export POETRY_VIRTUALENVS_PATH=${microblogpub_venv}
        cd ${microblogpub_app}
        poetry install
    )
}

microblogpub_initialize_db() {
    (
        export PATH="${microblogpub_bin_pyenv}:$PATH"
        cd ${microblogpub_app}
        export POETRY_VIRTUALENVS_PATH=${microblogpub_venv}
        poetry run inv migrate-db
    )
}

# updates python environment and initializes/updates database
microblogpub_update () {
    ynh_print_info --message="Updating microblogpub"
    (
        export PATH="${microblogpub_bin_pyenv}:$PATH"
        cd ${microblogpub_app}
        export POETRY_VIRTUALENVS_PATH=${microblogpub_venv}
        poetry run inv update
    )
}

microblogpub_set_version() {
    version_file="${microblogpub_app}/app/_version.py"
    app_package_version=$(ynh_app_package_version)
    echo "VERSION_COMMIT = \"ynh${app_package_version}\"" > $version_file
}

microblogpub_initial_setup() {
    (
        # Setup initial configuration
        export PATH="${microblogpub_bin_pyenv}:$PATH"
        cd ${microblogpub_app}
        export POETRY_VIRTUALENVS_PATH=${microblogpub_venv}
        poetry run inv yunohost-config --domain="${domain}" --username="${username}" --name="${name}" --summary="${summary}" --password="${password}"
        poetry run inv compile-scss
        ## the following worked, but left the rest of the data in the app/data directory
        ## "data" as part of the path to microblog.pubs data directory seems hardcoded.
        ## symlinking to the the data directory seems to work, so I'll stop this as an
        ## attempt to move the database only
        ## it might come in handy later when trying to move the database to mariadb
        ## 
        ## the yunohost app configuration wizard does not contain sqlalchemy_database (yet)
        # echo "sqlalchemy_database = \"$data_dir/microblogpub.db\"" >> ${microblogpub_app}/data/profile.toml
    )
}

# At the moment the data dir for microblog.pub cannot be configured and is hard coded into the
# scripts. So we'll move it and symlink it.
microblogpub_move_data() {
    # if $data_dir empty move data
    if [[ $(ls $data_dir | wc -l) -eq 0 ]]; then
        mv ${microblogpub_app}/data/* "${data_dir}"
        if [[ -e "${microblogpub_app}/data/.gitignore" ]]; then 
            rm "${microblogpub_app}/data/.gitignore"
        fi
        rmdir "${microblogpub_app}/data"
    else
        ynh_print_info --message="Directory $data_dir not empty - re-using old data"
        mv "${microblogpub_app}/data" "${microblogpub_app}/data-new-install-$(date '+%Y-%m-%d_%H-%M-%S_%N')"
        # TODO: ./inv.sh compile-scss - nur hier oder generell?
    fi
    # after moving or deleting symlink
    ln -s "${data_dir}" "${microblogpub_app}/data"
}
