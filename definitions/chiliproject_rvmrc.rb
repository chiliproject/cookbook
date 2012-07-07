define :chiliproject_rvmrc, :name => "default", :instance => {} do
  inst = chiliproject_instance(params[:instance])

  if ENV['MY_RUBY_HOME'] && ENV['MY_RUBY_HOME'].include?('rvm')
    begin
      rvm_path = File.dirname(File.dirname(ENV['MY_RUBY_HOME']))
      rvm_lib_path = File.join(rvm_path, 'lib')
      $LOAD_PATH |= [rvm_lib_path]
      require 'rvm'

      current_env = RVM.current.environment_name
      execute "rvm --rvmrc '#{current_env}'" do
        cwd deploy_to
        user "root"
        group "root"
        umask "0022"

        creates "#{deploy_to}/.rvmrc"
      end

      file "#{inst['deploy_to']}/shared/setup_load_paths.rb" do
        source "setup_load_paths.rb"
        owner inst['user']
        group inst['group']
        mode "0640"
      end

      node.run_state['chiliproject_deploy_symlinks'].merge!(
        "setup_load_paths.rb" => "config/setup_load_paths.rb"
      )
    rescue LoadError
      warn "Not setting up RVM as it is unavailable currently. This is optional."
    end
  end
end
