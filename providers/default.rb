# Support whyrun
def whyrun_supported?
  true
end

action :install do
  set_default_attributes

  user(new_resource.user) do
    comment       new_resource.name.capitalize
    home          new_resource.home
    shell         "/bin/bash"
    supports      :manage_home => true
  end

  directory(@new_resource.clone_path) do
    recursive true
  end

  repo = git(new_resource.name) do
    repository    new_resource.repository
    revision      new_resource.revision
    destination   new_resource.clone_path
    action        :sync
    notifies      :run, "bash[compile #{new_resource.name}]", :immediately
  end

  new_resource.updated_by_last_action(repo.updated_by_last_action?)

  src_directory = ::File.join(new_resource.clone_path, 'src')
  conf_file = ::File.join(new_resource.home, "#{new_resource.name}.conf")

  bash "compile #{new_resource.name}" do
    code          new_resource.compile_cmd || "cd src; make -f makefile.unix clean; make -f makefile.unix USE_UPNP= #{new_resource.executable}"
    cwd           new_resource.clone_path
    action        :nothing
    notifies      :run, "bash[strip #{new_resource.name}]", :immediately
  end

  bash "strip #{new_resource.name}" do
    code          "strip #{new_resource.executable}"
    cwd           src_directory
    action        :nothing
  end

  file ::File.join(new_resource.clone_path, 'src', new_resource.executable) do
    owner         new_resource.user
    group         new_resource.group
    mode          0500
  end

  link ::File.join(new_resource.home, "#{new_resource.name}d") do
    to            ::File.join(new_resource.clone_path, 'src', new_resource.executable)
    owner         new_resource.user
    group         new_resource.group
  end

  directory new_resource.data_dir do
    owner         new_resource.user
    group         new_resource.group
    mode          0700
  end

  file conf_file do
    owner         new_resource.user
    group         new_resource.group
    mode          0440
    content       config_content
  end

  template "/etc/init/#{new_resource.name}d.conf" do
    source        "upstart.conf.erb"
    mode          0700
    cookbook      "multicoin"
    variables(
      :user => new_resource.user,
      :group => new_resource.group,
      :data_dir => new_resource.data_dir,
      :conf_path => conf_file,
      :executable_name => "#{new_resource.name}d",
      :executable_path => ::File.join(new_resource.home, "#{new_resource.name}d"),
      :autostart => new_resource.autostart,
      :respawn_times => new_resource.respawn_times,
      :respawn_seconds => new_resource.respawn_seconds
    )
  end
end

def set_default_attributes
  @new_resource.user(@new_resource.user || @new_resource.name)
  @new_resource.group(@new_resource.group || @new_resource.name)
  @new_resource.home(@new_resource.home || ::File.join('/home', @new_resource.name))
  @new_resource.executable(@new_resource.executable || "#{@new_resource.name}d")
  @new_resource.clone_path(@new_resource.clone_path || ::File.join('/opt', 'crypto_coins', @new_resource.name))
  @new_resource.data_dir(@new_resource.data_dir || ::File.join(@new_resource.home, 'data'))
  @new_resource.autostart(@new_resource.autostart)
  @new_resource.respawn_times(@new_resource.respawn_times)
  @new_resource.respawn_seconds(@new_resource.respawn_seconds)
end

def config_hash
  # Set RPC Creds
  @new_resource.conf['rpcuser'] = @new_resource.rpcuser
  @new_resource.conf['rpcpassword'] = @new_resource.rpcpassword
  @new_resource.conf['rpcport'] = @new_resource.rpcport
  @new_resource.conf['port'] = @new_resource.port
  # Daemoize the process
  @new_resource.conf['daemon'] = 1
  @new_resource.conf['server'] = 1
  @new_resource.conf['pid'] = "/tmp/#{@new_resource.Acronymn}.pid"
  # Peer Connectivity 
  @new_resource.conf['irc'] = 0
  @new_resource.conf['dns'] = 1
  @new_resource.conf['forcednseed'] = 1
  # Info Callbacks
  @new_resource.conf['alertnotify'] = "alertnotify=/usr/bin/alertnotify %s"
  @new_resource.conf['blocknotify'] = "blocknotify=/usr/bin/alertblock /usr/bin/#{@new_resource.Acronymn}.push"
  # Blockchain Storage
  @new_resource.conf['txindex'] = 1
  @new_resource.conf['keypool'] = 1000
  # Transaction Creation Settings
  @new_resource.conf['sendfreetransactions'] =1
  # Remote Access
  @new_resource.conf['rpcallowip'] = ['10.46.73.169']
  # Add extra config options
  if @new_resource.extra_config and @new_resource.extra_config.is_a?(Hash)
    @new_resource.extra_config.each do |key, value|
      @new_resource.conf[key] = value
    end
  end
  # Return result
  return @new_resource.conf
end

def config_content
  content = ""
  config_hash.each do |key, value|
    case value
    when Array
      value.each do |part|
        content << "#{key}=#{part}\n"
      end
    when NilClass
      # do nothing
    else
      content << "#{key}=#{value}\n"
    end
  end
  return content
end
