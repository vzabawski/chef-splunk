#
# Cookbook:: chef-splunk
# Recipe:: service
#
# Copyright:: 2014-2016, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
if node['splunk']['is_server']
  directory splunk_dir do
    owner splunk_runas_user
    group splunk_runas_user
    mode '755'
  end

  directory "#{splunk_dir}/var" do
    owner splunk_runas_user
    group splunk_runas_user
    mode '711'
  end

  directory "#{splunk_dir}/var/log" do
    owner splunk_runas_user
    group splunk_runas_user
    mode '711'
  end

  directory "#{splunk_dir}/var/log/splunk" do
    owner splunk_runas_user
    group splunk_runas_user
    mode '700'
  end
end

if node['splunk']['accept_license']
  # ftr = first time run file created by a splunk install
  execute "#{splunk_cmd} enable boot-start --accept-license --answer-yes --no-prompt" do
    only_if { File.exist? "#{splunk_dir}/ftr" }
    notifies :create, 'template[/etc/init.d/splunk]'
  end
end

# If we run as splunk user do a recursive chown to that user for all splunk
# files if a few specific files are root owned.
ruby_block 'splunk_fix_file_ownership' do
  block do
    checkowner = []
    checkowner << "#{splunk_dir}/etc/users"
    checkowner << "#{splunk_dir}/etc/myinstall/splunkd.xml"
    checkowner << "#{splunk_dir}/"
    checkowner.each do |dir|
      next unless File.exist? dir
      FileUtils.chown_R(splunk_runas_user, splunk_runas_user, splunk_dir) if File.stat(dir).uid.eql?(0)
    end
  end
  not_if { node['splunk']['server']['runasroot'] }
end

Chef::Log.info("Node init package: #{node['init_package']}")

template '/etc/systemd/system/splunkd.service' do
  source 'splunk-systemd.erb'
  mode '644'
  variables(
    splunkdir: splunk_dir,
    splunkcmd: splunk_cmd,
    runasroot: node['splunk']['server']['runasroot']
  )
  notifies :run, 'execute[systemctl daemon-reload]'
  only_if { node['init_package'] == 'systemd' }
end

execute 'systemctl daemon-reload' do
  action :nothing
end

template '/etc/init.d/splunk' do
  source 'splunk-init.erb'
  mode '700'
  variables(
    splunkdir: splunk_dir,
    splunkuser: splunk_runas_user,
    splunkcmd: splunk_cmd,
    runasroot: node['splunk']['server']['runasroot'] == true
  )
  notifies :restart, 'service[splunk]'
end

service 'splunk' do
  supports status: true, restart: true
  provider splunk_service_provider
  action %i[start enable]
end
