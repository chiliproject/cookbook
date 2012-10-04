# If you use this definition by yourself, make sure to pass a properly setup
# instance. You can create one using the chiliproject_instance helper from a
# databag item
#
# extend ChiliProject::Helpers
# inst = chiliproject_instance "my_instance"

define :chiliproject_plugins, :name => nil, :instance => {} do
  inst = params[:instance]

  # Flag for remembering if any plugin is updated here
  plugin_updated = false

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

      force_deploy = plugin.has_key?('force_deploy') ? plugin['force_deploy'] : inst['force_deploy']
      deploy_action = force_deploy ? :force_deploy : :deploy

      plugin_resource = deploy_revision "ChiliProject plugin #{name} for #{inst['id']}" do
        repository plugin['repository']
        revision plugin['revision'] || "HEAD"
        scm_provider scm

        deploy_to plugin['deploy_to']
        action deploy_action

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
      end

      plugin_provider = plugin_resource.provider.new(plugin_resource, plugin_resource.run_context)
      release_slug = plugin_provider.send(:release_slug)

      plugin['release_path'] = plugin['deploy_to'] + "/releases/#{release_slug}"
      node.run_state['chiliproject_plugin_symlinks'].merge!(
        plugin['release_path'] => "vendor/plugins/#{name}"
      )
      if plugin['callback']
        node.run_state['chiliproject_plugin_callbacks'][name] = {
          'callback' => plugin['callback'],
          'plugin' => plugin
        }
      end

      unless ::File.exist?(plugin_resource.current_path) && plugin['release_path'] == File.readlink(plugin_resource.current_path)
        plugin_updated = true
      end
    end
  end

  # Force a full deployment of the app if a plugin was changed or removed.
  # We have to make sure that all migrations and potentially overridden
  # start scripts are properly run.

  existing_plugins = Dir.glob("#{inst['deploy_to']}/current/vendor/plugins/*").select{|f| File.symlink?(f)}
  # To play it save, we select only plugins that are handled by us
  existing_plugins.select{|p| File.readlink(p).start_with?("#{inst['deploy_to']}/shared/plugins")}
  new_plugins = node.run_state['chiliproject_plugin_symlinks'].values.collect{|p| "#{inst['deploy_to']}/current/#{p}"}

  if plugin_updated || (existing_plugins.sort != new_plugins.sort)
    Chef::Log.info "Forcing deployment of ChiliProject instance #{inst['id']} as one or more plugins were updated, installed, or removed"
    inst['force_deploy'] = true
  end
end
