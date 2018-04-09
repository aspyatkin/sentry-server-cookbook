require 'digest'

include_recipe 'libxml2::default'
include_recipe 'libxslt::default'
include_recipe 'libffi::default'

package 'libjpeg-dev' do
  action :install
end

id = 'sentry-server'

instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)

basedir = ::File.join('/opt', 'sentry')

directory basedir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

virtualenv_path = ::File.join(basedir, '.venv')

python_virtualenv virtualenv_path do
  python '2'
  user instance.user
  group instance.group
  action :create
end

requirements_file = ::File.join(basedir, 'requirements.txt')

cookbook_file requirements_file do
  source 'requirements.txt'
  owner instance.user
  group instance.group
  mode 0644
  action :create
end

pip_requirements requirements_file do
  user instance.user
  group instance.group
  virtualenv virtualenv_path
  action :install
end


include_recipe 'database::postgresql'

postgres_root_username = 'postgres'

postgresql_connection_info = {
  host: '127.0.0.1',
  port: 5432,
  username: postgres_root_username,
  password: secret.get("postgres:password:#{postgres_root_username}")
}

postgresql_database 'sentry_db' do
  connection postgresql_connection_info
  action :create
end

postgresql_database_user 'sentry_user' do
  connection postgresql_connection_info
  database_name 'sentry_db'
  password secret.get('postgres:password:sentry_user')
  privileges [:all]
  action [:create, :grant]
end

conf_file = ::File.join(basedir, 'sentry.conf.py')

template conf_file do
  source 'sentry.conf.py.erb'
  owner instance.user
  group instance.group
  variables(
    sentry_host: '127.0.0.1',
    sentry_port: 9000,
    sentry_web_workers: node[id]['config']['web']['workers'],
    sentry_uwsgi: true,
    sentry_max_stacktrace_frames: node[id]['config']['max_stacktrace_frames'],
    pg_host: '127.0.0.1',
    pg_port: 5432,
    pg_name: 'sentry_db',
    pg_username: 'sentry_user',
    pg_password: secret.get('postgres:password:sentry_user'),
    redis_host: '127.0.0.1',
    redis_port: 6379,
    redis_db: 1,
    ssl: node[id]['security']['ssl']
  )
  sensitive true
  mode 0644
end

conf_file_checksum = ::Digest::SHA256.file(conf_file).hexdigest

new_conf_file = ::File.join(basedir, 'config.yml')

fqdn = nil
if node[id]['fqdn'].nil?
  fqdn = instance.fqdn
else
  fqdn = node[id]['fqdn']
end

template new_conf_file do
  source 'sentry.config.yml.erb'
  owner instance.user
  group instance.group
  variables(
    admin_email: node[id]['config']['admin_email'],
    secret_key: secret.get('sentry:secret_key'),
    url_prefix: "http#{node[id]['security']['ssl'] ? 's' : ''}://#{fqdn}",
    redis_host: '127.0.0.1',
    redis_port: 6379,
    redis_db: 1,
    smtp_host: secret.get('sentry:smtp:host'),
    smtp_port: secret.get('sentry:smtp:port'),
    smtp_username: secret.get('sentry:smtp:username'),
    smtp_password: secret.get('sentry:smtp:password'),
    smtp_tls: secret.get('sentry:smtp:tls'),
    smtp_from: secret.get('sentry:smtp:from')
  )
  sensitive true
end

new_conf_file_checksum = ::Digest::SHA256.file(new_conf_file).hexdigest

python_execute 'Run Sentry database migration' do
  command '-m sentry upgrade --noinput'
  cwd basedir
  user instance.user
  group instance.group
  environment(
    'SENTRY_CONF' => basedir
  )
  action :run
end

namespace = 'sentry'

supervisor_service "#{namespace}.web" do
  command "#{::File.join(virtualenv_path, 'bin', 'sentry')} run web"
  process_name 'web'
  numprocs 1
  numprocs_start 0
  priority 300
  autostart true
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user instance.user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.web-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.web-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => "#{::File.join(virtualenv_path, 'bin')}:%(ENV_PATH)s",
    'SENTRY_CONF' => basedir,
    'INTERNAL_SENTRY_CONF_FILE_CHECKSUM' => conf_file_checksum,
    'INTERNAL_SENTRY_NEW_CONF_FILE_CHECKSUM' => new_conf_file_checksum
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

supervisor_service "#{namespace}.worker" do
  command "#{::File.join(virtualenv_path, 'bin', 'sentry')} run worker -n worker-%(process_num)02d"
  process_name 'worker_%(process_num)02d'
  numprocs node[id]['config']['worker']['processes']
  numprocs_start 0
  priority 300
  autostart true
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user instance.user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.worker-%(process_num)02d-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.worker-%(process_num)02d-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => "#{::File.join(virtualenv_path, 'bin')}:%(ENV_PATH)s",
    'SENTRY_CONF' => basedir,
    'INTERNAL_SENTRY_CONF_FILE_CHECKSUM' => conf_file_checksum,
    'INTERNAL_SENTRY_NEW_CONF_FILE_CHECKSUM' => new_conf_file_checksum
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

supervisor_service "#{namespace}.cron" do
  command "#{::File.join(virtualenv_path, 'bin', 'sentry')} run cron"
  process_name 'cron'
  numprocs 1
  numprocs_start 0
  priority 300
  autostart true
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup false
  killasgroup false
  user instance.user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.cron-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.cron-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  environment(
    'PATH' => "#{::File.join(virtualenv_path, 'bin')}:%(ENV_PATH)s",
    'SENTRY_CONF' => basedir,
    'INTERNAL_SENTRY_CONF_FILE_CHECKSUM' => conf_file_checksum,
    'INTERNAL_SENTRY_NEW_CONF_FILE_CHECKSUM' => new_conf_file_checksum
  )
  directory basedir
  serverurl 'AUTO'
  action :enable
end

supervisor_group namespace do
  programs [
    "#{namespace}.web",
    "#{namespace}.worker",
    "#{namespace}.cron"
  ]
  action [:enable, :start]
end

ngx_vhost_variables = {
  fqdn: fqdn,
  access_log: ::File.join(node['nginx']['log_dir'], 'sentry_access.log'),
  error_log: ::File.join(node['nginx']['log_dir'], 'sentry_error.log'),
  sentry_host: '127.0.0.1',
  sentry_port: 9000,
  ssl: node[id]['security']['ssl'],
}

if node[id]['security']['ssl']
  tls_rsa_certificate fqdn do
    action :deploy
  end

  tls_rsa_item = ::ChefCookbook::TLS.new(node).rsa_certificate_entry(fqdn)

  ngx_vhost_variables.merge!({
    ssl_rsa_certificate: tls_rsa_item.certificate_path,
    ssl_rsa_certificate_key: tls_rsa_item.certificate_private_key_path,
    hsts_max_age: node[id]['security']['hsts_max_age'],
    oscp_stapling: node.chef_environment.start_with?('production'),
    scts: node.chef_environment.start_with?('production'),
    scts_rsa_dir: tls_rsa_item.scts_dir,
    hpkp: node.chef_environment.start_with?('production'),
    hpkp_pins: tls_rsa_item.hpkp_pins,
    hpkp_max_age: node[id]['security']['hpkp_max_age'],
    use_ec_certificate: node[id]['security']['use_ec_certificate']
  })

  if node[id]['security']['use_ec_certificate']
    tls_ec_certificate fqdn do
      action :deploy
    end

    tls_ec_item = ::ChefCookbook::TLS.new(node).ec_certificate_entry(fqdn)

    ngx_vhost_variables.merge!({
      ssl_ec_certificate: tls_ec_item.certificate_path,
      ssl_ec_certificate_key: tls_ec_item.certificate_private_key_path,
      scts_ec_dir: tls_ec_item.scts_dir,
      hpkp_pins: (ngx_vhost_variables[:hpkp_pins] + tls_ec_item.hpkp_pins).uniq,
    })
  end
end

nginx_site 'sentry' do
  template 'nginx.conf.erb'
  variables ngx_vhost_variables
  action :enable
end

cli_script = ::File.join(basedir, 'cli.py')

cookbook_file cli_script do
  source 'sentry_cli.py'
  owner instance.user
  group instance.group
  mode 0644
  action :create
end

secret.get('sentry:superusers', default: {}).each do |username, password|
  env_name_rand = "PWD_#{[*?A..?Z].sample(8).join}"

  env_command = {
    'SENTRY_CONF' => basedir
  }
  env_command[env_name_rand] = password

  python_execute "Create Sentry superuser <#{username}>" do
    command "cli.py create superuser #{username} #{env_name_rand}"
    cwd basedir
    user instance.user
    group instance.group
    environment env_command
    action :run
  end
end

secret.get('sentry:users', default: {}).each do |username, password|
  env_name_rand = "PWD_#{[*?A..?Z].sample(8).join}"

  env_command = {
    'SENTRY_CONF' => basedir
  }
  env_command[env_name_rand] = password

  python_execute "Create Sentry user <#{username}>" do
    command "cli.py create user #{username} #{env_name_rand}"
    cwd basedir
    user instance.user
    group instance.group
    environment env_command
    action :run
  end
end

node[id]['config']['entities'].each do |organization_name, organization_data|
  env_command = {
    'SENTRY_CONF' => basedir
  }

  python_execute "Create Sentry organization <#{organization_name}>" do
    command "cli.py create organization \"#{organization_name}\""
    cwd basedir
    user instance.user
    group instance.group
    environment env_command
    action :run
  end

  organization_data.fetch('owners', []).each do |owner_username|
    python_execute "Create Sentry organization <#{organization_name}> owner <#{owner_username}>" do
      command "cli.py update organization \"#{organization_name}\" --owner #{owner_username}"
      cwd basedir
      user instance.user
      group instance.group
      environment env_command
      action :run
    end
  end

  organization_data.fetch('members', []).each do |member_username|
    python_execute "Create Sentry organization <#{organization_name}> member <#{member_username}>" do
      command "cli.py update organization \"#{organization_name}\" --member #{member_username}"
      cwd basedir
      user instance.user
      group instance.group
      environment env_command
      action :run
    end
  end

  organization_data.fetch('teams', {}).each do |team_name, team_data|
    python_execute "Create Sentry team <#{team_name}> in organization <#{organization_name}>" do
      command "cli.py create team \"#{organization_name}\" \"#{team_name}\""
      cwd basedir
      user instance.user
      group instance.group
      environment env_command
      action :run
    end

    team_data.fetch('members', []).each do |team_member|
      python_execute "Create Sentry team <#{team_name}> member <#{team_member}> in organization <#{organization_name}>" do
        command "cli.py update team \"#{organization_name}\" \"#{team_name}\" --member #{team_member}"
        cwd basedir
        user instance.user
        group instance.group
        environment env_command
        action :run
      end
    end

    team_data.fetch('projects', []).each do |project_name|
      python_execute "Create Sentry team <#{team_name}> project <#{project_name}> in organization <#{organization_name}>" do
        command "cli.py create project \"#{organization_name}\" \"#{team_name}\" \"#{project_name}\""
        cwd basedir
        user instance.user
        group instance.group
        environment env_command
        action :run
      end
    end
  end
end

script_dir = ::File.join(basedir, 'scripts')

directory script_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

cleanup_script_filepath = ::File.join(script_dir, 'cleanup')
cleanup_enabled = node[id]['cleanup']['enabled']

template cleanup_script_filepath do
  source 'cleanup.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    target_user: instance.user,
    virtualenv_path: virtualenv_path,
    sentry_conf_dir: basedir,
    sentry_cleanup_days: node[id]['cleanup']['days']
  )
  if cleanup_enabled
    action :create
  else
    action :delete
  end
end

cron 'sentry_cleanup' do
  unless node[id]['cleanup']['cron']['mailto'].nil? && node[id]['cleanup']['cron']['mailfrom'].nil?
    command %Q(#{cleanup_script_filepath} 2>&1 | mail -s "Cron sentry_cleanup" -a "From: #{node[id]['cleanup']['cron']['mailfrom']}" #{node[id]['cleanup']['cron']['mailto']})
  else
    command "#{cleanup_script_filepath}"
  end
  minute node[id]['cleanup']['cron']['minute']
  hour node[id]['cleanup']['cron']['hour']
  day node[id]['cleanup']['cron']['day']
  month node[id]['cleanup']['cron']['month']
  weekday node[id]['cleanup']['cron']['weekday']

  if cleanup_enabled
    action :create
  else
    action :delete
  end
end

backup_enabled = node[id]['backup']['enabled']

s3backup_postgres_database 'sentry_database' do
  db_host '127.0.0.1'
  db_port 5432
  db_name 'sentry_db'
  db_username 'sentry_user'
  db_password secret.get('postgres:password:sentry_user')
  aws_iam_access_key_id secret.get("aws:iam:#{node[id]['backup']['aws']['iam']['account_alias']}:access_key_id")
  aws_iam_secret_access_key secret.get("aws:iam:#{node[id]['backup']['aws']['iam']['account_alias']}:secret_access_key")
  aws_s3_bucket_region node[id]['backup']['aws']['s3']['bucket_region']
  aws_s3_bucket_name node[id]['backup']['aws']['s3']['bucket_name']
  schedule(
    mailto: node[id]['backup']['cron']['mailto'],
    mailfrom: node[id]['backup']['cron']['mailfrom'],
    minute: node[id]['backup']['cron']['minute'],
    hour: node[id]['backup']['cron']['hour'],
    day: node[id]['backup']['cron']['day'],
    month: node[id]['backup']['cron']['month'],
    weekday: node[id]['backup']['cron']['weekday']
  )
  if backup_enabled
    action :create
  else
    action :delete
  end
end
