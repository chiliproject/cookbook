define :chiliproject_plugins, :name => nil, :instance => {} do
  inst = params[:instance]

  directory "#{inst['deploy_to']}/shared/plugins" do
    owner inst['user']
    group inst['group']
    mode '0755'
  end

  inst['plugins'].each_pair do |name, plugin|
    plugin['repository_type'] ||= "git" if repository = plugin['repository']
    plugin['deploy_to'] = "#{inst['deploy_to']}/shared/plugins/#{name}"

    [plugin['deploy_to'], "#{plugin['deploy_to']}/shared"].each do |dir|
      directory dir do
        owner inst['user']
        group inst['group']
        mode '0755'
        recursive true
      end
    end

    case plugin['repository_type']
    when "git", "subversion"
      scm = Chef::Provider.const_get(plugin['repository_type'].capitalize)

      chiliproject_deploy_key "ChiliProject plugin #{name} for #{inst['id']}" do
        instance inst
        deploy_to plugin['deploy_to']
        deploy_key plugin['deploy_key']
      end

      deploy_revision "ChiliProject plugin #{name} for #{inst['id']}" do
        repository plugin['repository']
        revision plugin['revision'] || "HEAD"
        scm_provider scm

        deploy_to plugin['deploy_to']

        force_deploy = plugin.has_key?('force_deploy') ? plugin['force_deploy'] : inst['force_deploy']
        action force_deploy ? :force_deploy : :deploy

        user inst['user']
        group inst['group']

        case plugin['provider']
        when "git"
          ssh_wrapper "#{plugin['deploy_to']}/deploy-ssh-wrapper" if plugin['deploy_key']
          shallow_clone true
        end

        purge_before_symlink []
        create_dirs_before_symlink []
        symlinks({})
        symlink_before_migrate({})
        migrate false

        after_restart do
          # register this plugin so we can later set it up properly
          # when deploying the main instance
          node.run_state['chiliproject_plugin_symlinks'].merge!(
            release_path => "vendor/plugins/#{name}"
          )

          plugin['release_path'] = release_path
          if plugin['callback']
            node.run_state['chiliproject_plugin_callbacks'][name] = {
              'callback' => plugin['callback'],
              'plugin' => plugin
            }
          end
        end
      end
    end
  end
end
