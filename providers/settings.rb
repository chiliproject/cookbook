include Chef::Mixin::ShellOut

action :set do
  settings = new_resource.values

  if new_resource.delayed
    set_later(settings)
  else
    set_now(settings)
  end
end

protected

def set_later(settings)
  inst = new_resource.instance

  node.run_state['chiliproject_delayed_settings'] ||= {}
  node.run_state['chiliproject_delayed_settings'][inst['id']] ||= {}

  settings.each_pair do |k, v|
    node.run_state['chiliproject_delayed_settings'][inst['id']][k] = v
  end

  unless (resource_collection.find("chiliproject_settings[Delayed Settings for #{inst['id']}]") rescue nil)
    chiliproject_settings "Delayed Settings for #{inst['id']}" do
      action :nothing
      values node.run_state['chiliproject_delayed_settings'][inst['id']]
      instance new_resource.instance
      delayed false
    end

    # http://www.sharp-tools.net/archives/002187.html
    new_resource.notifies :set, new_resource.resources(:chiliproject_settings => "Delayed Settings for #{inst['id']}"), :delayed
    new_resource.updated_by_last_action(true)
  end
end

def set_now(settings)
  inst = new_resource.instance

  command = "script/console"
  opts = {
    :input => settings.collect{ |k, v| "Setting[#{k.inspect}] = #{v.inspect}" }.join("\n"),
    :cwd => inst['deploy_to'] + "/current",
    :user => inst['user'],
    :group => inst['group'],
    :environment => {
      'HOME' => inst['deploy_to'],
      'RAILS_ENV' => inst['rails_env']
    },
    :log_level => :info,
    :log_tag => new_resource.to_s
  }
  if STDOUT.tty? && !Chef::Config[:daemon] && Chef::Log.info?
    opts[:live_stream] = STDOUT
  end

  converge_by("Set #{settings.keys.map(&:to_s).join(", ")}") do
    result = shell_out!(command, opts)
    Chef::Log.info("#{new_resource} ran successfully")
  end
  new_resource.updated_by_last_action(true)

  if new_resource.name == "Delayed Settings for #{inst['id']}"
    # clear the saved up setting changes
    node.run_state['chiliproject_delayed_settings'] ||= {}
    node.run_state['chiliproject_delayed_settings'][inst['id']] = {}
  end
end
