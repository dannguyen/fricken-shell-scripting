# boot_instance

require 'aws/ec2'
require 'yaml'
require 'pry'

server_opts = YAML.load_file('./config/servers/defaults.yml')
@logger = Logger.new(STDOUT)

aws_opts = server_opts['cloud']

## Just incase I've decided to set up my own ENV stuff

ssh_config = {
  'CheckHostIP' => 'no',
  'StrictHostKeyChecking' => 'no',
  'UserKnownHostsFile' => '/dev/null',
  'User' => 'ec2-user',
  'IdentityFile' => File.expand_path( server_opts["secret_key_file"])
}

## secure the identity file
File.chmod 0600, File.expand_path(ssh_config['IdentityFile'])


## Configure AWS with credentials and region
aws_access_creds = {}
if( cred_file = aws_opts['access_creds'] )
  aws_access_creds = YAML.load_file File.expand_path( File.join('..', cred_file) , __FILE__)
end

AWS.config(  aws_access_creds.merge(region: aws_opts['region']) )



my_inst = AWS::EC2.new.instances.create(
  image_id: server_opts['image_id'],
  count: 1,
  security_groups: server_opts['security_groups'],
  key_name: server_opts['key_name'],
  instance_type: server_opts['instance_type'],
  availability_zone: server_opts['availability_zone']
)

# add some tags
instance_tags = Hash[Array(server_opts['tags'])]
instance_tags['Name'] ||= server_opts['name']
instance_tags.each_pair{ |tname, tval| my_inst.tag( tname, value: tval ) }


# wait until instance is running and get the public dns name
while :pending == my_inst.status
  sleep 5
  @logger.info "Waiting for instance #{my_inst.instance_id} state to become running"
end


ssh_options = ssh_config.collect{ |k, v| "-o #{k}=#{v}"}.join(' ')

while true
  sleep 3
  break if system "ssh -o ConnectTimeout=10 #{ssh_options} #{my_inst.dns_name} exit 0 2>/dev/null"
  @logger.info "waiting for instance #{my_inst.instance_id} / #{my_inst.dns_name} to start sshd "
end


if( deploy_key_file = server_opts['deploy_key'] )
  deploy_key_file = File.expand_path deploy_key_file
  system "ssh #{ssh_options} #{my_inst.dns_name} 'test -e .ssh/id_dsa && exit 0; mkdir -p .ssh; while read line; do echo $line; done > .ssh/id_dsa; chmod 0600 .ssh/id_dsa' < #{deploy_key_file}"
end


Array( server_opts["scripts"] ).each do |script|
  system "ssh #{ssh_options} #{my_inst.dns_name} sudo bash -x < #{script}"
end

@logger.info "ssh #{ssh_options} #{my_inst.dns_name}"
